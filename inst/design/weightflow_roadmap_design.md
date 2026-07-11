# weightflow — Design Document, Extension 2 (Development Roadmap)

**Planned weighting methods, source fusion, and workflow automation**

Companion to `weightflow_design.md` (core, 0.1) and `weightflow_poststrat_design.md` (Extension 1, 0.2). This document specifies the intended contents of releases 0.3 through 0.6. It is a *design commitment*, not yet an implementation: each section fixes the function signatures, the seam it attaches to, the theory it rests on, and the automation discipline it must preserve, so that the work can be picked up incrementally without re-litigating the architecture.

Nothing here breaks 0.1/0.2. Every addition lands on one of the three reserved seams from the core document — Seam 1 (target constructors), Seam 2 (method registry), Seam 3 (weight-pipeline ledger) — and reuses the existing `wf_dims` / `wf_target` / `wf_weights` / `wf_precheck` / `wf_diagnostics` classes and the frozen condition taxonomy. The guiding principle from 0.1 carries through unchanged: **precheck → execute → diagnose**, with every automated decision surfaced as a reviewable, provenance-logged artifact rather than a silent internal choice.

---

## 1. Roadmap at a glance

| Release | Theme | New public API | Seam |
|---|---|---|---|
| 0.3 | Dual-source fusion | `wf_blend()`, `wf_compose()` | 3 |
| 0.4 | Non-probability correction | `wf_propensity()`, `wf_target_propensity()` | 2, 1 |
| 0.5 | Variance & uncertainty | `wf_replicates()`, `wf_variance()` | 3 |
| 0.6 | Bounded calibration & automation aids | `wf_calibrate(method="greg"/"logit")`, `wf_auto_trim()`, `wf_suggest_ladder()`, `wf_report()` | 2, + helpers |
| later | Small-area modelling | `method = "mrp"`, `redistribute = "model"` | 2 |

The ordering reflects marginal value to the current national-survey project: fusion (0.3) is the final deliverable's missing link; propensity (0.4) is the correct treatment the online sample currently lacks; variance (0.5) is unavoidable for any reported figure. Bounded calibration and the automation aids (0.6) are quality-of-life improvements over the current "rake-then-trim, hand-authored ladders" workflow.

---

## 2. Release 0.3 — Dual-source fusion (Seam 3)

### 2.1 Problem

The project produces two weight sets from two sources: an online sample calibrated by `wf_rake()` and an offline sample calibrated by `wf_poststrat()`. The deliverable is a single set of population estimates (e.g. pass rates by subpopulation) that combines both. This is the classic **dual-frame / probability-plus-nonprobability composite estimation** problem (Hartley 1962; Elliott & Valliant 2017): each source yields an estimate of the same population quantity, combined as a convex combination with weights lambda and 1 - lambda.

### 2.2 Two hard design rules, learned from the earlier analysis

**Rule A - compose at the estimator level, never pool the weights.** For a ratio-type quantity such as a pass rate, `blend(rate) = lambda * rate_online + (1 - lambda) * rate_offline` is *not* equal to computing a rate on a table where the two weight sets are stacked. Stacking lets each source's contribution be silently governed by its weight-sum in each cell rather than by the intended lambda. `wf_blend()` therefore computes each source's per-cell estimate first, then combines; the lambda the user sets is exactly the lambda that acts.

**Rule B - lambda varies by cell (or at least by group), it is not one global constant.** The relative reliability of the two sources differs across cells: an urban high-education cell may have thousands of online respondents and few offline; a rural elderly cell the reverse. A single global lambda (e.g. a blanket 4:1) over-trusts online where it is thin - precisely where its raked/collapsed estimate is an extrapolation - which is a substantive error, not just an efficiency loss. The default lambda is data-driven per cell.

### 2.3 `wf_blend()`

```r
wf_blend(
  online, offline,                 # two wf_weights objects (raking / poststrat)
  by_cell,                         # dimensions defining the fusion cells
  lambda = c("neff","inverse_variance","fixed"),
  lambda_fixed = NULL,             # required iff lambda = "fixed" (scalar or per-group)
  outcome = NULL,                  # 0/1 or numeric column -> returns fused estimate
  level = c("cell","group"),       # granularity at which λ is computed & applied
  trim_lambda = c(0.05, 0.95),     # clamp data-driven λ away from degenerate 0/1
  sensitivity = TRUE               # sweep global online-share and report stability
)
```

λ strategies:

- **`"neff"`** — λ_cell ∝ effective sample size n/deff of each source in that cell. This is the standard composite weight and correctly discounts the online source for its post-raking design effect (measured, not nominal — the online sample is large in name but its deff is high after correcting self-selection).
- **`"inverse_variance"`** — λ_cell = Var(est_offline) / (Var(est_online) + Var(est_offline)), the minimum-variance optimal composite when both estimates are approximately unbiased. Naturally cell-varying; degenerate cells (one source empty) collapse to the other source automatically.
- **`"fixed"`** — a user constant, e.g. `lambda_fixed = 0.8` for a 4:1 prior preference. Permitted, but flagged in diagnostics with the discrepancy between the stated λ and the neff/inverse-variance λ, so a hand-picked 4:1 cannot masquerade as an optimal one.

Returns a `wf_blend_result` carrying: the fused per-cell (and aggregated) estimate with its variance; the **effective λ actually applied per cell**; each source's per-cell estimate, variance, and effective sample size; and, when `sensitivity = TRUE`, the fused estimate as the global online share is swept (e.g. 0.3–0.9) so the analyst sees whether the conclusion depends on the λ choice. `outcome = NULL` returns fused *weights* per cell instead of an estimate, for downstream use.

### 2.4 `wf_compose()` — the pipeline ledger

Independently of fusion, real production weighting is a chain: design weight → nonresponse adjustment → calibration → trimming. `wf_compose(w1, w2, ...)` multiplies successive `wf_weights` stages per unit and concatenates their provenance, yielding one auditable object whose history lists every stage, its method, and its settings. This is the substrate on which 0.5's replicate weights run (a replicate is the whole chain re-executed on resampled data), so it ships in 0.3 even though its headline use arrives later.

### 2.5 Assumptions surfaced, not hidden

`wf_blend()` prints, and stores in provenance, the exchangeability/unbiasedness assumptions the fusion rests on: convex combination is meaningful only if both sources are approximately unbiased for the cell quantity, and the online source's unbiasedness holds only under "the calibration variables explain the full selection mechanism." The sensitivity sweep is the operational hedge against that assumption. This mirrors the core principle that the package makes its methodological commitments explicit and checkable.

---

## 3. Release 0.4 — Non-probability correction via propensity (Seams 2 & 1)

### 3.1 Problem

The online sample is self-selected. Raking it to population margins assumes those margins capture the whole selection bias; residual selection on anything outside the calibration variables is untouched. The principled remedy uses the offline **probability** sample as a reference to model the *propensity to enter the online sample*, then corrects for it — turning "pretend the online sample is a probability sample" into "estimate and invert its selection mechanism." The project already has the ideal reference sample in hand.

### 3.2 Method (pseudo-design weights, then calibration)

Stack the online sample and the offline reference; fit a model for membership (online vs reference) on the shared demographic (and any available auxiliary) variables; convert fitted propensities into **pseudo-design weights** for the online units (inverse-propensity, or the equivalent kernel/weighting variants). These pseudo-design weights then feed `wf_rake()` or `wf_poststrat()` as the *initial* weights of a second stage — exactly the `init_weight` slot Extension 1 already exposes. So propensity correction is a first-stage weight producer, not a replacement for calibration; the two compose cleanly via `wf_compose()`.

### 3.3 API

```r
wf_target_propensity(          # Seam 1: builds the reference frame + model spec
  online, reference,
  formula,                     # membership model, e.g. member ~ age5 + edu5 + cx
  method = c("logit","rf","gbm"),  # base R glm default; ML variants behind Suggests
  by = NULL
)

wf_propensity(                 # Seam 2: fit, diagnose, emit pseudo-design weights
  online, target_propensity,
  weight = c("ipw","kernel","matching"),
  stabilize = TRUE,            # stabilized IPW to tame extreme weights
  trim = NULL                  # optional propensity-weight trimming
)                              # -> wf_weights (stage 1), feed as init_weight to stage 2
```

### 3.4 Discipline and diagnostics

Propensity work has well-known failure modes, each mapped to the existing condition taxonomy and precheck philosophy: non-overlap / poor common support (online units with propensities near the boundary → `wf_warning_quality`, with a support-overlap report); model misspecification (a balance table before/after weighting, checking whether weighting actually equalizes covariate distributions between online and reference); extreme weights (stabilization on by default, trimming available). `wf_propensity()` returns, alongside the weights, a **balance diagnostic** and an **overlap diagnostic**, so the precheck→execute→diagnose loop holds here too: fit is never accepted blindly.

### 3.5 Base-R first

The default membership model is `glm(family = binomial)` — zero new dependencies. Random-forest / gradient-boosting propensity variants register behind `Suggests:` (ranger / xgboost), selected by `method=`, never required. This keeps the core installable everywhere while allowing stronger models where available.

---

## 4. Release 0.5 — Variance and uncertainty (Seam 3)

### 4.1 Problem

Every weighted figure the project reports — a pass rate, a subpopulation mean — needs a variance, or it is a point with no interval. Analytic variance formulas for a multi-stage design → nonresponse → calibration → fusion pipeline are intractable to write by hand and fragile to maintain. Replication is the standard, general answer: re-run the *entire weighting pipeline* on resampled data and read the variability of the result.

### 4.2 `wf_replicates()` and `wf_variance()`

```r
wf_replicates(
  pipeline,                    # a wf_compose() chain (or a single wf_weights)
  method = c("bootstrap","jackknife","brr"),
  R = 500,                     # bootstrap replicates
  strata = NULL, clusters = NULL,  # respect the offline design structure
  seed = NULL
)                              # -> wf_replicate_weights (R columns of weights)

wf_variance(
  replicate_weights, estimator,   # a function(weights, data) -> scalar/vector
  data
)                              # -> estimate, variance, CI per quantity
```

Because 0.3's `wf_compose()` captures the pipeline as a replayable object with full provenance, a replicate is literally that object re-executed on a resampled input — including re-raking, re-collapsing, re-blending — so the variance reflects the *calibration* uncertainty, not just sampling of raw responses (a common and serious omission). For the offline probability sample, resampling respects its strata and clusters; for the online sample, the resampling reflects whichever first-stage (propensity) model produced its weights. The fused estimator from `wf_blend()` is a valid `estimator` argument, giving confidence intervals on the final composite pass rates.

### 4.3 Determinism and cost

Replication is embarrassingly parallel (each replicate independent); the reserved `parallel = TRUE` path applies. Seeds are stored in provenance for exact reproducibility. Because the R kernel for raking/poststrat is already fast (§11 of the respective docs), R = 500 replicates on national-scale data remain tractable on a laptop; where they are not, the reserved Rcpp kernel is the escape hatch.

---

## 5. Release 0.6 — Bounded calibration and automation aids

### 5.1 GREG / linear and logit calibration (Seam 2)

Raking is one special case of calibration estimation (Deville–Särndal). The general family lets the analyst bound the weight adjustment. **Logit calibration** produces weights bounded within a user range *by construction*, which merges two steps the current workflow keeps separate: aligning margins and keeping weights from exploding. Where `wf_rake()` today is followed by a separate trimming pass, `wf_calibrate(method = "logit", bounds = c(L, U))` does both at once, with no post-hoc distortion of the margins that trimming introduces. `method = "greg"` (linear calibration) is the unbounded GREG estimator, useful when an auxiliary continuous variable (not just categorical margins) is available. Both register on the same Seam 2 interface as raking and poststrat and consume the same `wf_target`; `wf_rake()` remains sugar for `method = "raking"`.

### 5.2 `wf_auto_trim()` — data-driven trim bounds

Trim limits are currently hand-set (e.g. 15× the mean). This helper sweeps a grid of candidate caps and, for each, reports the **bias–variance frontier**: the incremental margin/cell residual introduced versus the design-effect reduction obtained. It then recommends the loosest cap meeting a stated criterion (e.g. "design effect below X" or "residual below Y"), turning a purely judgemental number into a reproducible, defensible choice. It only *recommends*; the analyst sets the final bound, consistent with the discipline that automated steps propose and humans approve.

### 5.3 `wf_suggest_ladder()` — collapse-ladder drafting

Extension 1 requires collapse ladders to be pre-declared (correctly — merges must be auditable). This helper does not remove that requirement; it lowers its cost. It scans, across all groups, which dimensions are sparse and in what order collapsing them loses the least information, and emits a **draft** `wf_collapse_ladder` for the analyst to review and edit. The workflow shifts from authoring a ladder on a blank page to amending a proposed one — the same "precheck produces, human approves" pattern as `wf_suggest_collapse()` in 0.1.

### 5.4 `wf_report()` — the weighting quality dossier

A single call that assembles the full weighting-quality report from a `wf_weights` (or composed pipeline): per-group design effect, effective sample size, weight-distribution extremes, trimming impact, margin/cell residuals, fusion λ and its sensitivity, propensity balance/overlap where applicable, and a plain-language verdict per group. Output is a structured object with `print()`, `as.data.frame()`, and an optional rendered document (Markdown/HTML) suitable for a methods appendix. This replaces the current hand-assembled tables with one reproducible, standardized artifact — the natural capstone of the precheck→execute→diagnose discipline extended across the whole pipeline.

---

## 6. Later — Small-area modelling (Seam 2)

MRP (multilevel regression with post-stratification) is the principled route when cells are genuinely empty and small-area estimates are required. It fits a multilevel model to the outcome (or cell means), borrowing strength across cells via partial pooling to predict **every** cell including the empty ones, then aggregates against the joint population table already available in `wf_target$joint`. It attaches at two reserved points: as `method = "mrp"` in the registry, and as `redistribute = "model"` in `wf_poststrat()` (an orphan cell is filled by a model prediction rather than proportional reallocation). It shifts from a weighting paradigm to a modelling one, so its outputs are labelled as model-based estimates and its assumptions documented accordingly; multilevel fitting brings a `Suggests:` dependency (e.g. lme4 or a Stan backend), never required by the core.

---

## 7. Cross-cutting commitments

Every roadmap item honours the invariants established in 0.1/0.2, so the package grows without drifting:

- **Discipline preserved.** Each new method ships with its own precheck-side diagnostics (overlap, balance, bias–variance frontier, λ sensitivity) and refuses to accept a fit silently; automated choices are always drafts a human ratifies.
- **Seams, not surgery.** No roadmap item edits the core engines; each is a new constructor (Seam 1), a registry entry (Seam 2), or a pipeline stage (Seam 3). The `.wf_methods` registry unifies raking, poststrat, greg, logit, propensity, and mrp under one `wf_calibrate()` interface.
- **Base-R core, optional acceleration.** Every default path is base R with zero hard dependencies; ML propensity models, Rcpp kernels, parallel replication, and Stan-backed MRP all live behind `Suggests:` and are selected explicitly.
- **Provenance and reproducibility.** Every stage — fusion λ, propensity model, trim bound, replicate seed — is recorded in the result's provenance, so any reported figure is reconstructable from its own metadata.
- **Assumptions surfaced.** Where a method rests on an untestable assumption (online unbiasedness, cell exchangeability, model form), the package states it in output and provides the corresponding sensitivity or balance check rather than burying it.

---

## 8. Consolidated public API after 0.6 (planned)

```
# core (0.1)
wf_dims(); wf_target_population(); wf_target_reference(); wf_target_manual()
wf_target_shrink(); wf_precheck(); wf_suggest_collapse(); wf_apply_collapse()
wf_rake(); wf_diagnose()

# post-stratification (0.2)
wf_collapse_ladder(); wf_plan_poststrat(); wf_poststrat()

# unified method interface (0.6)
wf_calibrate(method = "raking" | "poststrat" | "greg" | "logit" | "propensity" | "mrp")

# fusion & pipeline (0.3, 0.5)
wf_blend(); wf_compose(); wf_replicates(); wf_variance()

# non-probability correction (0.4)
wf_target_propensity(); wf_propensity()

# automation aids (0.6)
wf_auto_trim(); wf_suggest_ladder(); wf_report()
```

Each block is independently shippable; the table in §1 is the intended order, but the seams make any reordering safe should project priorities change.
