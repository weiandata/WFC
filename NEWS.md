# WFC 1.0.0

* Standardized the maintainer and company contact identities, adopted GPL
  (>= 2), and added `inst/COPYRIGHTS` for dependency copyright boundaries.

API freeze and publication release. This release closes the 0.10 -> 1.0
roadmap by freezing the public WFC core API, documenting the deprecation policy,
and adding release infrastructure for CRAN and the bilingual pkgdown site.

* Declared the 1.0 public API freeze for exported signatures, core S3 object
  fields, classed conditions, and stable English programmatic keys. Additive
  changes remain allowed; removals or semantic breaks require a major version.
* Added an installed stability contract under `inst/stability/api-freeze.md`,
  including the frozen exported signatures, object-field expectations,
  condition taxonomy, and the one-minor-release deprecation policy.
* Added the reserved `wf_warning_deprecated` warning class for future
  deprecations.
* Refreshed `cran-comments.md` for the 1.0 initial CRAN submission and the
  current local check status.
* Added `_pkgdown.yml` for the 1.0 publication site, with the English reference
  and article structure plus a link to the existing Simplified Chinese README.
* Updated the WFCstudio integration contract to pin the sibling beta to the WFC
  1.0 API boundary without adding GUI code or hard dependencies to WFC core.

# WFC 0.16.0

Performance engineering. This release adds opt-in fork parallelism and optional
progress reporting for the long-running calibration paths while preserving
serial defaults and deterministic result ordering.

* Added `parallel = TRUE` to `wf_rake()` and `wf_poststrat()` so independent
  target groups can run through `parallel::mclapply` on Unix-alike platforms.
  Windows falls back to serial execution with a note.
* Added `parallel = TRUE` to `wf_replicates()` so replicate refit closures can
  run concurrently after the replicate multipliers have been generated.
* Added `progress = TRUE` to the same APIs. When the optional `cli` package is
  installed, WFC shows a progress bar; otherwise execution silently falls back
  to the existing no-progress behavior.
* Parallel execution captures classed WFC warnings and errors from child tasks
  and replays them in the main process, preserving the package's condition
  contracts.
* Provenance now records whether parallel/progress execution was requested and
  how many workers were used. The R IPF kernel remains the default because this
  pass did not introduce an Rcpp dependency.

# WFC 0.15.0

Methods II and influence diagnostics. This release adds panel attrition
weighting, high-influence unit diagnostics, and Fay's BRR while preserving the
existing `wf_weights` and replicate-variance contracts.

* Added `wf_attrition()` to estimate inverse-retention weights for panel
  nonresponse. It fits base-R logistic retention models, supports grouped fits,
  stabilization, optional trimming, retention-probability diagnostics, and
  balance checks against the full prior wave.
* `wf_attrition()` returns `wf_attrition_weights`, an additive subclass of
  `wf_weights`, so attrition correction can be chained through `wf_compose()`
  before calibration.
* Added `wf_influence()` to rank units by weight ratio, squared-weight design
  effect share, leave-one-out design effect, and optional target-margin share.
* Added Fay's BRR through `wf_replicates(method = "brr", rho = ...)`, with the
  standard BRR behavior preserved at `rho = 0`.
* `as_svrepdesign()` now preserves Fay BRR metadata by forwarding `rho` to
  survey when available.
* `wf_report()` now carries attrition balance and retention-probability
  sections for attrition-stage weights.
* Added the attrition-weighting and influence-diagnostics vignette.
* Added focused tests for attrition validation, composition, influence
  diagnostics, Fay multipliers, and Fay replicate metadata.

# WFC 0.14.0

Method-family expansion. This release adds soft calibration and entropy
balancing while keeping both methods inside the existing `wf_calibrate()` and
`wf_weights` contracts.

* Added `wf_calibrate(method = "soft")`, a penalized calibration engine that
  preserves exact group totals while allowing declared margin relaxation within
  scalar or per-dimension tolerances.
* Soft calibration now treats zero-support target categories as relaxable only
  when the achieved-vs-target gap remains inside the declared tolerance, and it
  records a `$relaxation` audit table for every group, dimension, and category.
* Added `wf_calibrate(method = "ebal")` for entropy balancing. It minimizes
  divergence from base weights under exact categorical margins and optional
  continuous moment targets supplied through `moments = c(var = mean)`.
* Entropy balancing records per-group KL divergence and an optional `$moments`
  table with target and achieved means.
* `wf_report()` now carries soft-calibration relaxation and entropy-moment
  sections, and `wf_pipeline()` / `wf_run()` can execute both new methods.
* Added the soft-calibration and entropy-balancing vignette.
* Added focused tests for infeasible soft margins, moment validation, pipeline
  execution, reporting sections, and method-specific printing.

# WFC 0.13.0

Production infrastructure. This release makes recurring weighting rounds
declarative, auditable, and drift-checkable while continuing to run through the
existing weighting engines.

* Added `wf_pipeline()` to declare a serializable target/stage/validation
  specification with a stable provenance hash.
* Added `wf_run()` to execute population, reference, manual, or ready-target
  pipelines, optionally prepend a propensity pseudo-weight stage, accept numeric
  base weights for replicate refit closures, and attach pipeline provenance to
  the returned `wf_weights`.
* Added `wf_validate()` to compare new weights against a reference release on
  group coverage, design effect, effective sample size, total weights, optional
  margin residuals, and matched-unit weight-ratio drift.
* Added `wf_audit_export()` to write dependency-free JSON audit records with
  provenance, pipeline metadata, optional guided-workflow ledgers, input hashes,
  and user-supplied metadata.
* Pipeline validation thresholds now emit classed `wf_warning_quality`
  conditions and preserve structured validation tables for downstream review.
* Added the production-infrastructure vignette covering pipeline specs, runs,
  drift checks, replicate refit closures, and audit exports.

# WFC 0.12.0

Ecosystem interoperability. This release connects WFC results to survey/srvyr
and broom-style consumers without changing any calibration engine or adding a
hard dependency.

* Added `as_svydesign()` to align `wf_weights` with analysis data by exact unit
  ID and return a standard `survey.design2`, including cluster, strata, finite
  population, nesting, and downstream survey-estimator support.
* Added `as_svrepdesign()` for `wf_replicate_weights`, mapping bootstrap, JK1,
  JKn, and BRR metadata while preserving WFC scale/rscales and full-estimate
  MSE semantics. `survey::svymean()` reproduces `wf_variance()` standard errors
  for all three WFC replication methods.
* Both bridges enforce unique, identical ID sets, preserve input row order and
  provenance, reject reserved controls, avoid input mutation, and raise a
  classed `wf_error_dependency` when the suggested survey package is absent.
* Added conditionally registered `generics::tidy()`, `glance()`, and
  `augment()` methods for weights, diagnostics, blend results, and variance
  results. They return base data frames with stable English programmatic keys;
  `augment.wf_weights()` appends `.weight` and `.feature` by exact ID.
* Added the ecosystem-interoperability vignette and froze the separate,
  no-statistics WFCstudio sibling-package integration contract.
* Raised the minimum R version from 3.5.0 to 3.6.0, the release that introduced
  delayed S3 registration for suggested-package generics.

# WFC 0.11.0

Guided workflow and localized output. This release adds an auditable
non-specialist path over the existing engines without changing their numerical
semantics or stable object keys.

* Added `wf_autoweigh()` to build or accept a target, enforce precheck,
  apply only declared category-collapse remediations, route to raking,
  post-stratification, or bounded logit calibration, and return weights,
  diagnostics, a manager report, final inputs, and an ordered decision ledger.
* Automatic method selection now chooses post-stratification only when both a
  reviewed collapse ladder and `min_cell` are supplied; otherwise it uses
  raking and never silently selects bounded logit calibration.
* Guided raking integrates `wf_auto_trim()`: finite recommendations may be
  confirmed and applied, while no-trim and no-solution outcomes are recorded
  explicitly. Non-interactive runs remain reproducible and auditable.
* Added matched English and Simplified Chinese output catalogs with explicit
  argument, option, and locale resolution. `wf_report()` and all package plot
  methods now localize human-facing labels while preserving English object,
  column, condition, action, and ledger keys.
* Added `wf_autoweigh_result` printing, aligned structured artifacts, localized
  narration, classed refusal paths, and focused tests for every routing,
  remediation, trim, and language branch.
* `wf_apply_collapse()` now keeps retained joint population cells synchronized
  with collapsed margins, so guided post-stratification cannot use stale joint
  categories after remediation.

# WFC 0.10.0

Usability foundations. This release adds review and communication layers over
the existing weighting engines without changing their numerical semantics.

* Added `wf_report()` with manager and analyst projections, structured
  method-specific sections, Markdown output, dependency-free escaped HTML,
  `print()`, and `as.data.frame()` support. Reports accept both `wf_weights` and
  `wf_blend_result` objects.
* Added `wf_auto_trim()` to sweep candidate caps, expose the bias-variance
  frontier, preserve candidate warnings/failures, and recommend the loosest cap
  satisfying declared design-effect and margin-residual criteria.
* Added `wf_suggest_ladder()` to draft adjacent category merges from worst-group
  support, order dimensions by affected sample share, and return a validated
  ladder for explicit human review.
* Added base-graphics methods for weights, diagnostics, automatic trim results,
  blend sensitivity, and propensity overlap/balance.
* Propensity results now inherit from the additive `wf_propensity_weights`
  subclass and retain fitted propensity vectors for overlap plotting while
  remaining fully compatible with `wf_weights` consumers.
* The `lang` argument on `wf_report()` reserves the 0.11 localization contract;
  0.10 reports are English-only and reject unsupported languages explicitly.

# WFC 0.9.1

Stabilization release. No public API signatures or weighting-method semantics
changed.

* Added an external oracle test comparing grouped raking, including non-uniform
  initial weights, against `survey::rake()`.
* Added determinism and order-invariance contracts for sample rows and
  calibration dimensions.
* Added an 80% line-coverage CI gate and a reproducible performance benchmark
  harness for the core raking workloads.
* Added the three workflow vignettes promised by the core design: the complete
  precheck-execute-diagnose loop, population-data mapping, and dirty-data /
  infeasibility handling.
* Regenerated `wfc_example` with support in every documented joint cell. The
  former deterministic pattern passed marginal precheck but made the README
  raking quick start structurally non-convergent.
* Fixed `wf_precheck()` so an NA grouping key is reported as `na_group` without
  leaking into group arithmetic and causing an unrelated missing-value error.
* Added CRAN release notes and refreshed contributor, package-name, data-policy,
  and verification instructions after the rename to WFC.

# WFC 0.9.0

Package renamed from `weightflow` to `WFC`: CRAN already hosts an unrelated
survey-weighting package named `weightflow`, so the old name could not be
submitted and would shadow installations from CRAN.

* Renamed the package, GitHub URLs, and test harness accordingly. All `wf_*`
  function names, classes, and condition classes are unchanged.
* Renamed the bundled example dataset `weightflow_example` to `wfc_example`
  (regenerated by `data-raw/make-wfc-example.R`).
* Added the Extension 3 design document (`inst/design/wfc_future_design.md`)
  committing the 0.10 -> 1.0 roadmap: guided workflow, localized reports,
  survey/broom bridges, pipeline infrastructure, soft calibration, entropy
  balancing, attrition weighting, and influence diagnostics; with reference
  prototypes under `inst/reference/wfc_future_*.R`.

# WFC 0.8.1

Audit fixes for robustness and CRAN/GitHub compliance. No new public API.

* `wf_rake()` now raises a classed `wf_error_convergence` (with the group, the
  worst dimension, and the last deviation) when IPF fails to converge within
  `max_iter`, instead of silently recording a non-converged log row. This
  implements the behaviour specified in the core design document.
* `wf_poststrat()` now validates the `init_weight` column name and raises
  `wf_error_schema` when it is absent, matching `wf_rake()`.
* `wf_propensity()` now rejects NA values in membership-model predictors with a
  classed `wf_error_input` instead of failing inside `glm()` with an unrelated
  message.
* `wf_rake()` and `wf_poststrat()` provenance now records the installed package
  version instead of a hard-coded historical string.
* Vectorized respondent-to-resolved-cell assignment in `wf_poststrat()`
  (per-ladder-level instead of per-row), improving large-sample performance.
* Declared `Imports: stats, utils`, set a real package maintainer, and extended
  `.Rbuildignore` (nested `.DS_Store`, `.worktrees`, root tarballs).
* Added a GitHub Actions `R CMD check --as-cran` workflow across R devel,
  release, and oldrel on Linux, macOS, and Windows.

# WFC 0.8.0

Bounded calibration. Adds a Deville-Sarndal calibration engine to
`wf_calibrate()` with linear (GREG) and bounded (logit) distances.

* Added `wf_calibrate(method = "greg")` for the linear GREG estimator.
* Added `wf_calibrate(method = "logit", bounds = c(L, U))` for calibration with
  weights bounded within `(L, U)` by construction, merging margin alignment and
  weight trimming into one step.
* Both calibrate to the existing `wf_target` margins, honour `init_weight`, and
  return the standard `wf_weights` so they compose and support replicate
  variance.

# WFC 0.7.0

Variance and uncertainty. Adds replicate-weight variance that re-runs the
calibration pipeline per replicate, so estimates carry standard errors and
confidence intervals including calibration uncertainty.

* Added `wf_replicates()` to generate re-calibrated replicate weights via
  Rao-Wu bootstrap, stratified delete-one jackknife, or BRR, driven by a user
  refit closure.
* Added `wf_variance()` to combine replicate weights and an estimator into an
  estimate, variance, standard error, and normal or percentile confidence
  interval, using one unified combining rule across methods.
* Added an `init_weight` argument to `wf_rake()` so raking can consume replicate
  base weights (unchanged behaviour when `NULL`).

# WFC 0.6.0

Non-probability correction via propensity. Adds a two-step propensity workflow
that corrects a self-selected online sample against an offline probability
reference, emitting pseudo-design weights that feed calibration as initial
weights.

* Added `wf_target_propensity()` to stack an online sample and a probability
  reference into a membership-model specification.
* Added `wf_propensity()` to fit a base-R logistic membership model and emit
  inverse-propensity pseudo-design weights as a `wf_weights` stage, with
  stabilized IPW on by default and optional trimming.
* Added overlap / common-support and covariate-balance diagnostics, with a
  `wf_warning_quality` on poor support.

# WFC 0.5.0

Dual-source fusion. Adds estimator-level online/offline fusion without stacking
row-level weights.

* Added `wf_blend()` for estimator-level dual-source fusion of online and
  offline `wf_weights` objects.
* Added `wf_blend_result` with source estimates, applied lambda values,
  diagnostics, sensitivity output, and provenance.
* Added support for `neff`, `inverse_variance`, and `fixed` lambda strategies.

# WFC 0.4.0

Weight pipeline ledger. Adds a composition layer for chaining weighting stages
while preserving stage-level provenance.

* Added `wf_compose()` to multiply compatible `wf_weights` stages into one
  auditable `wf_weights` result.
* Added ID-safe composition with classed errors for duplicate IDs, missing IDs,
  different ID sets, incompatible groups, and invalid weights.
* Added optional composed-weight normalization with `normalize = "mean1"` and
  `normalize = "sum"`.

# WFC 0.3.0

Foundation API completion. Extends the calibration workflow with manual targets,
target shrinkage, and a unified dispatcher, while preserving the existing raking
and post-stratification engines.

* Added `wf_target_manual()` to build a canonical target from a ready-made long
  margin table.
* Added `wf_target_shrink()` to shrink a target toward a reference target.
* Added `wf_suggest_collapse()` to turn precheck findings into a reviewable
  collapse plan using ladders declared in `wf_dims()`.
* Added `wf_apply_collapse()` to apply a collapse plan consistently to both the
  sample and the target.
* Added `wf_calibrate()`, a unified dispatcher that routes to `wf_rake()` or
  `wf_poststrat()` while preserving the common `wf_weights` contract.

# WFC 0.2.0

Post-stratification engine. Adds cell-level calibration against joint population
targets, with reviewable collapse ladders and planning.

* Added joint population targets via `wf_target_population(..., keep_joint = TRUE)`.
* Added `wf_collapse_ladder()` to declare post-stratification collapse ladders.
* Added `wf_plan_poststrat()` to plan cell resolution before execution.
* Added `wf_poststrat()` to run cell-level post-stratification, returning a
  `cell_report` and `collapse_map`.

# WFC 0.1.0

Initial package foundation and core raking workflow.

* Added `wf_dims()` to declare schema-agnostic calibration dimensions.
* Added `wf_target_population()` and `wf_target_reference()` target constructors.
* Added `wf_precheck()` for structured sample/target compatibility checks.
* Added `wf_rake()` grouped raking (iterative proportional fitting) with trimming
  cycles and a missing-data policy.
* Added `wf_diagnose()` weight and margin diagnostics.
* Added the simulated `weightflow_example` dataset for examples and tests.
