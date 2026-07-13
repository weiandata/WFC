# WFC

<!-- badges: start -->
[![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Lifecycle: stable](https://img.shields.io/badge/lifecycle-stable-brightgreen.svg)](https://lifecycle.r-lib.org/articles/stages.html#stable)
[![License: GPL >= 2](https://img.shields.io/badge/license-GPL%20%3E%3D%202-blue.svg)](LICENSE)
[![R >= 3.6.0](https://img.shields.io/badge/R-%3E%3D%203.6.0-blue.svg)](https://cran.r-project.org/)
<!-- badges: end -->

**English** | [Simplified Chinese](README.zh-CN.md)

Status: Active

Owner: WEIAN DATA Engineering

`WFC` is a workflow-oriented R package for survey weighting and raking. It
emphasizes a disciplined **precheck → execute → diagnose** loop for multi-source
survey calibration, with schema-agnostic dimensions and canonical target objects
that stay consistent across raking and post-stratification engines.

## Why WFC

Most weighting scripts fail silently: a category is missing from the target, a
cell is too thin to estimate, or a group total drifts after trimming. `WFC`
turns those failure modes into first-class, reviewable steps.

- **Precheck before you calibrate.** `wf_precheck()` compares the sample against
  the target and reports incompatibilities before any weights are computed.
- **One target contract, many sources.** Build a canonical `wf_target` from
  external population data, a weighted reference sample, or a manual margin table.
- **Reviewable category collapsing.** Declare a collapse ladder up front, get
  suggested merges from precheck findings, and apply them consistently to both
  sample and target.
- **Raking and post-stratification behind one dispatcher.** `wf_calibrate()`
  returns the same `wf_weights` contract regardless of method.
- **Diagnostics as a habit.** `wf_diagnose()` closes every workflow with weight
  and margin diagnostics.

## Installation

Install the development version from GitHub:

```r
# install.packages("remotes")
remotes::install_github("weiandata/WFC")
```

Or build from a source tarball:

```r
install.packages("WFC_1.0.0.tar.gz", repos = NULL, type = "source")
```

## Workflow at a glance

```text
declare dims ──► build target ──► precheck ──► (collapse) ──► calibrate ──► diagnose
   wf_dims()      wf_target_*()   wf_precheck()  wf_suggest_    wf_rake() /   wf_diagnose()
                                                 collapse()     wf_poststrat()
                                                 wf_apply_      wf_calibrate()
                                                 collapse()
```

## Quick start

```r
library(WFC)

data(wfc_example)

dims <- wfc_example$dims
target <- wf_target_population(
  pop = wfc_example$population,
  key_map = c(gender = "gender", age = "age"),
  count = "count",
  dims = dims,
  by = "province"
)

precheck <- wf_precheck(wfc_example$sample, target, id = "id")
precheck

weights <- wf_rake(wfc_example$sample, target, id = "id")
wf_diagnose(weights, target = target)
```

## Guided workflow and localized output

WFC includes a one-call path over the same public constructors, precheck,
calibration engines, diagnostics, and reports. It never bypasses a blocking
precheck: automatic remediation is limited to collapse maps already declared in
`wf_dims()`, and every decision is recorded with stable machine-readable keys.

```r
guided <- wf_autoweigh(
  sample = wfc_example$sample,
  population = wfc_example$population,
  dims = dims,
  key_map = c(gender = "gender", age = "age"),
  count = "count",
  by = "province",
  id = "id",
  interactive = FALSE
)

guided$weights
guided$ledger[c("step", "action", "detail_key", "detail")]
```

`method = "auto"` uses post-stratification only when both a reviewed `ladder`
and `min_cell` are supplied; otherwise it uses raking. It never selects bounded
logit calibration automatically. Use `interactive = TRUE` when declared
collapses and finite trim recommendations should require confirmation.

Human-facing reports, guided narration, and plot labels support English and
Simplified Chinese. Stable object fields, condition classes, and ledger keys
remain English.

```r
wf_report(guided$weights, guided$target, lang = "zh_CN")
plot(guided$diagnostics, lang = "zh_CN")

options(wfc.lang = "zh_CN")
# Explicit `lang` overrides this option; an unrecognized session locale falls
# back to English.
```

See `vignette("guided-workflow", package = "WFC")` for method routing,
decision-ledger review, and automation boundaries.

## Ecosystem interoperability

WFC converts results into standard survey-package designs after a
strict, order-independent ID join. Suggested packages remain optional: WFC can
still be installed and loaded with only its base-R imports.

```r
analysis <- wfc_example$sample
analysis$outcome <- as.numeric(analysis$age == "young")

survey_design <- as_svydesign(
  guided$weights,
  analysis,
  id = "id"
)
survey::svymean(~outcome, survey_design)
```

`as_svrepdesign()` converts `wf_replicate_weights` to a standard
`svyrep.design`, preserving bootstrap, JK1/JKn, or BRR scales and reproducing
`wf_variance()` uncertainty. Because both outputs are ordinary survey objects,
an installed srvyr package can wrap them directly with
`srvyr::as_survey(survey_design)`.

Broom-style projections are conditionally registered against the suggested
`generics` package and return base data frames:

```r
generics::tidy(guided$weights)                    # unit-level weights
generics::glance(guided$diagnostics)              # one-row quality summary
augmented <- generics::augment(
  guided$weights,
  data = analysis,
  id = "id"
)
```

All bridges and augmenters require unique, identical unit-ID sets. They never
silently discard unmatched rows. See
`vignette("ecosystem-interoperability", package = "WFC")` for replicate
variance equivalence and supported result projections.

## Post-stratification

Post-stratification uses joint population cells instead of marginal totals. Build
the target with `keep_joint = TRUE`, declare a reviewable collapse ladder, then
plan and execute the cell calibration.

```r
target_joint <- wf_target_population(
  pop = wfc_example$population,
  key_map = c(gender = "gender", age = "age"),
  count = "count",
  dims = dims,
  by = "province",
  keep_joint = TRUE
)

ladder <- wf_collapse_ladder(
  dims,
  level1 = list(age = c(young = "all", old = "all"))
)

plan <- wf_plan_poststrat(
  wfc_example$sample,
  target_joint,
  min_cell = 2,
  ladder = ladder
)
plan

post <- wf_poststrat(
  wfc_example$sample,
  target_joint,
  min_cell = 2,
  ladder = ladder,
  id = "id"
)
wf_diagnose(post)
```

## Foundation API

Manual margins can be converted directly to a target and calibrated through the
unified dispatcher. A target can also be shrunk toward a reference target before
calibration.

```r
manual <- data.frame(
  dimension = c("gender", "gender", "age", "age"),
  category = c("female", "male", "young", "old"),
  value = c(55, 45, 60, 40)
)

target_manual <- wf_target_manual(manual, dims)
weights_manual <- wf_calibrate(
  wfc_example$sample,
  target_manual,
  method = "raking",
  id = "id"
)
wf_diagnose(weights_manual)
```

## Pipeline Ledger

Multiple weighting stages can be composed into one auditable `wf_weights` object.
Composition matches units by ID, multiplies stage weights, and stores each stage
in provenance.

```r
calibration <- wf_rake(wfc_example$sample, target, id = "id")

adjustment <- calibration
adjustment$data$weight <- rep(c(0.9, 1.1), length.out = nrow(adjustment$data))
adjustment$data$feature <- 1 / adjustment$data$weight
adjustment$provenance$method <- "nonresponse_adjustment_example"

final_weights <- wf_compose(adjustment, calibration, normalize = "mean1")
wf_diagnose(final_weights)
```

## Dual-Source Fusion

Online and offline calibrated sources can be fused at the estimator level with
`wf_blend()`. The function computes each source's cell estimate first, then
combines those estimates with the applied lambda recorded in the result.

```r
online <- wf_rake(wfc_example$sample, target, id = "id")
offline <- online

analysis_cols <- wfc_example$sample[c("id", "gender", "age")]
online$data <- merge(online$data, analysis_cols, by = "id", all.x = TRUE, sort = FALSE)
offline$data <- merge(offline$data, analysis_cols, by = "id", all.x = TRUE, sort = FALSE)

online$data$cell <- online$data$gender
offline$data$cell <- offline$data$gender
online$data$outcome <- as.numeric(online$data$age == "young")
offline$data$outcome <- as.numeric(offline$data$age == "young")

blend <- wf_blend(
  online,
  offline,
  by_cell = "cell",
  outcome = "outcome",
  lambda = "neff"
)

blend$estimates
blend$lambda
```

## Non-Probability Correction

A self-selected online sample can be corrected against an offline probability
reference by modelling its selection propensity. `wf_target_propensity()` stacks
the two samples into a membership-model specification; `wf_propensity()` fits a
base-R logistic model and emits inverse-propensity pseudo-design weights (a
`wf_weights` stage) that feed calibration as `init_weight` and compose via
`wf_compose()`. Overlap and covariate-balance diagnostics are attached, and poor
common support raises a `wf_warning_quality`.

```r
target <- wf_target_propensity(online, reference, member ~ gender + age)
stage1 <- wf_propensity(target, stabilize = TRUE)

stage1$overlap    # common-support report
stage1$balance    # covariate SMDs, unweighted vs pseudo-weighted

online$pw <- stage1$data$weight
calibrated <- wf_poststrat(online, pop_target, min_cell = 20, ladder = ladder,
                           init_weight = "pw", id = "id")
```

## Variance & Uncertainty

Any weighted estimate can carry a standard error and confidence interval that
include calibration uncertainty, via replicate weights. `wf_replicates()`
perturbs base weights (Rao-Wu bootstrap, jackknife, or BRR) and re-runs the
calibration pipeline on each replicate through a `refit` closure;
`wf_variance()` combines them with an estimator into an estimate, SE, and CI.

```r
refit <- function(data, weights) {
  data$.bw <- weights
  wf_rake(data, target, id = "id", init_weight = ".bw")
}

reps <- wf_replicates(sample, refit, method = "bootstrap", R = 500,
                      strata = "stratum", clusters = "psu", id = "id",
                      seed = 1)
wf_variance(reps, function(w, d) sum(w * d$y) / sum(w), sample)
```

## Bounded Calibration

`wf_calibrate()` also offers general calibration beyond raking and
post-stratification. `method = "greg"` is the linear GREG estimator;
`method = "logit"` produces weights bounded within `bounds = c(L, U)` by
construction, merging margin alignment and weight trimming into one step.
`method = "soft"` allows declared, audited margin relaxation, and
`method = "ebal"` performs entropy balancing for exact moment matching.

```r
# weights bounded between 0.3x and 3x the base weight
w <- wf_calibrate(sample, target, method = "logit", bounds = c(0.3, 3),
                  init_weight = "design_w", id = "id")
w$log   # per-group convergence and realized weight-ratio range
```

## Production and performance

Recurring production rounds can be declared as serializable pipelines and
validated against a reference release. Audit exports write dependency-free JSON
records with provenance, input hashes, and user metadata.

```r
spec <- wf_pipeline(
  target = list(
    mode = "population",
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    by = "province"
  ),
  stages = list(calibrate = list(method = "raking", id = "id")),
  validate = list(max_deff = 6, max_margin_dev = 0.01)
)

round1 <- wf_run(spec, wfc_example$sample, dims = dims,
                 population = wfc_example$population)
wf_validate(round1, weights, target = target)
```

Long grouped calibrations and replicate refits support opt-in fork parallelism
(capped at two workers for CRAN compliance) and optional `cli` progress bars:

```r
weights_parallel <- wf_rake(
  wfc_example$sample,
  target,
  id = "id",
  parallel = TRUE,
  progress = TRUE
)
```

## Usability foundations

The lower-level 0.10 review and communication tools remain available for expert
workflows.
`wf_auto_trim()` recommends rather than applies a cap; `wf_suggest_ladder()`
returns a draft and a validated ladder for explicit review; `wf_report()` turns
the structured diagnostics into manager or analyst output.

```r
trim_advice <- wf_auto_trim(
  wfc_example$sample,
  target,
  id = "id",
  caps = c(2, 4, 8)
)
trim_advice
plot(trim_advice)

report <- wf_report(weights, target, audience = "manager")
report

ladder_draft <- wf_suggest_ladder(
  wfc_example$sample,
  target,
  dims,
  min_cell = 25
)
ladder_draft
# After review, use ladder_draft$ladder where a post-strat ladder is required.
```

Base `plot()` methods are also available for `wf_weights`, `wf_diagnostics`,
`wf_blend_result`, and propensity-weight results, with `lang` controlling
human-facing labels.

## Function reference

| Stage | Function | Purpose |
| --- | --- | --- |
| Guided | `wf_autoweigh()` | Run target construction, precheck, declared remediation, calibration, diagnosis, reporting, and decision logging. |
| Bridge | `as_svydesign()` | Convert calibrated weights to a standard survey design by exact ID. |
| Bridge | `as_svrepdesign()` | Convert WFC replicate weights to a survey replicate design with equivalent uncertainty. |
| Tidy | `generics::tidy()` / `glance()` / `augment()` | Project WFC results into stable base data frames and join weights back to analysis data. |
| Dimensions | `wf_dims()` | Declare calibration dimensions and optional collapse ladders. |
| Target | `wf_target_population()` | Build a canonical target from external population data. |
| Target | `wf_target_reference()` | Build a target from a weighted reference sample. |
| Target | `wf_target_manual()` | Build a target from a manual long margin table. |
| Target | `wf_target_shrink()` | Shrink a target toward a reference target. |
| Precheck | `wf_precheck()` | Check sample/target compatibility before calibration. |
| Collapse | `wf_collapse_ladder()` | Declare a post-stratification collapse ladder. |
| Collapse | `wf_suggest_collapse()` | Suggest collapse plans from precheck findings. |
| Collapse | `wf_suggest_ladder()` | Draft a reviewable post-stratification ladder from sparse support. |
| Collapse | `wf_apply_collapse()` | Apply a collapse plan to sample and target. |
| Calibrate | `wf_calibrate()` | Dispatch to a calibration method (raking, post-strat, greg, or logit). |
| Calibrate | `wf_calibrate(method = "greg"/"logit"/"soft"/"ebal")` | Linear GREG, bounded logit, soft calibration, or entropy balancing. |
| Calibrate | `wf_rake()` | Grouped raking (iterative proportional fitting). |
| Calibrate | `wf_plan_poststrat()` | Plan post-stratification cell resolution. |
| Calibrate | `wf_poststrat()` | Run cell-level post-stratification. |
| Production | `wf_pipeline()` | Declare a serializable weighting round. |
| Production | `wf_run()` | Execute a declared pipeline. |
| Production | `wf_validate()` | Check weight drift against a reference release. |
| Production | `wf_audit_export()` | Write a JSON audit record. |
| Compose | `wf_compose()` | Compose multiple weighting stages into one auditable result. |
| Fusion | `wf_blend()` | Fuse online and offline estimates at the estimator level. |
| Propensity | `wf_target_propensity()` | Stack an online sample and a probability reference into a membership-model spec. |
| Propensity | `wf_propensity()` | Emit inverse-propensity pseudo-design weights with overlap and balance diagnostics. |
| Attrition | `wf_attrition()` | Estimate inverse-retention weights for panel nonresponse. |
| Influence | `wf_influence()` | Rank high-influence units for trimming and review. |
| Variance | `wf_replicates()` | Generate re-calibrated bootstrap/jackknife/BRR replicate weights. |
| Variance | `wf_variance()` | Combine replicate weights and an estimator into an estimate, SE, and CI. |
| Recommend | `wf_auto_trim()` | Recommend a trim cap from the bias-variance frontier. |
| Diagnose | `wf_diagnose()` | Diagnose calibrated weights and margins. |
| Report | `wf_report()` | Build manager/analyst quality dossiers in object, Markdown, or HTML form. |
| Visualize | `plot()` | Plot weights, diagnostics, trim frontiers, blend sensitivity, or propensity quality. |

All exported functions ship with full documentation. From R, use `?wf_rake`,
`help(package = "WFC")`, or `example(wf_target_population)`.

## Data policy

Private source spreadsheets and RData files under `private-data/` are **not
committed** and are **not** included in package builds. All examples and tests use
the simulated `wfc_example` dataset, generated by
`data-raw/make-wfc-example.R`.

## Project status

Version 1.0.0 freezes the public API for the WFC core. The stable scope now
includes raking, post-stratification, manual targets and shrinkage, collapse
planning, weight composition, dual-source fusion, propensity and attrition
correction, replicate-weight variance, bounded calibration, soft calibration,
entropy balancing, production pipelines, drift validation, audit exports,
quality reports, trim recommendations, ladder drafts, diagnostic plots,
survey/srvyr bridges, broom-style projections, bilingual human-facing output,
and opt-in parallel execution. The package was renamed from `weightflow` to
`WFC` at 0.9.0 after a CRAN name collision. See [`NEWS.md`](NEWS.md) for the
full changelog and `inst/stability/api-freeze.md` for the 1.0 compatibility
contract.

Design documents live in [`inst/design/`](inst/design/): the core design, the
post-stratification and roadmap extensions, and
[`wfc_future_design.md`](inst/design/wfc_future_design.md) — the 0.10 → 1.0
roadmap (guided workflow, ecosystem bridges, production infrastructure, soft
calibration). Reference prototypes for the roadmap live in
[`inst/reference/`](inst/reference/).

## Contributing

Contributions are welcome. Please read
[`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, the
test-driven workflow, and the language policy, and review the
[Code of Conduct](.github/CODE_OF_CONDUCT.md) before opening an issue or pull
request. Repository conventions for automated agents are documented in
[`AGENTS.md`](AGENTS.md).

## License

Released under the [GNU General Public License version 2 or later](LICENSE).
Copyright © 2026 WEIAN DATA TECH (Beijing) Co., Ltd. Dependency copyrights and
license boundaries are documented in [`inst/COPYRIGHTS`](inst/COPYRIGHTS).
