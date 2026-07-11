# Non-Probability Correction via Propensity 0.6.0 Design

## Goal

Add non-probability correction to `weightflow` by introducing
`wf_target_propensity()` and `wf_propensity()`, a two-step API for modeling the
online sample's self-selection against the offline probability sample and
emitting **pseudo-design weights** that feed the existing calibration engines as
initial weights.

The feature follows `inst/design/weightflow_roadmap_design.md` Release 0.4
(non-probability correction via propensity), adapted to the current package
sequence as version 0.6.0. It lands on two reserved seams from
`inst/design/weightflow_design.md`: **Seam 1** (target constructors) for
`wf_target_propensity()`, and **Seam 2** (method registry) for `wf_propensity()`.
It edits no core engine. The pseudo-design weights it produces are a first-stage
weight producer, not a replacement for calibration: they compose cleanly with
`wf_rake()` / `wf_poststrat()` via the existing `init_weight` slot and with
`wf_compose()` via the `wf_weights` contract.

## Scope

Version 0.6.0 will implement the base-R core of propensity correction:

- Add `wf_target_propensity()` to build the stacked reference frame and
  membership-model specification.
- Add `wf_propensity()` to fit the membership model, convert fitted propensities
  into pseudo-design weights, and return a `wf_weights` stage-1 object.
- Support `method = "logit"` (base R `glm(family = binomial)`) as the only fit
  backend.
- Support `weight = "ipw"` (inverse-propensity weighting) with stabilized IPW on
  by default and optional trimming.
- Return an overlap / common-support diagnostic and a covariate-balance
  diagnostic alongside the weights.
- Map failure modes onto the frozen condition taxonomy.

Version 0.6.0 will **not** implement random-forest / gradient-boosting fit
backends (`method = "rf"` / `"gbm"`), kernel or matching weight variants
(`weight = "kernel"` / `"matching"`), replicate-weight variance, bounded
calibration, or MRP. Those remain later roadmap items. The `method` and `weight`
arguments keep their full reserved vocabularies in the signature so later
releases add backends without an API break; unimplemented values raise a classed
`wf_error_input`.

## Public API

```r
wf_target_propensity(
  online,
  reference,
  formula,
  method = c("logit", "rf", "gbm"),
  by = NULL,
  id = NULL
)

wf_propensity(
  target,
  weight = c("ipw", "kernel", "matching"),
  stabilize = TRUE,
  trim = NULL
)
```

Only `weight = "ipw"` is executable in 0.6.0; `"kernel"` / `"matching"` are
accepted by `match.arg` and then abort as reserved, so later releases add them
without an API break.

### `wf_target_propensity()`

`online` and `reference` are data frames sharing the model covariates. `formula`
is a two-sided membership formula, e.g. `member ~ age5 + edu5`. The right-hand
side names the model predictors; the left-hand side names the membership
indicator column that the constructor creates (`1` for online rows, `0` for
reference rows). The constructor:

- Validates that `formula` is a two-sided formula with at least one RHS term.
- Validates that every RHS variable exists in both `online` and `reference`;
  a missing variable raises `wf_error_input`.
- Validates that the LHS name does not collide with an existing predictor.
- Stacks `online` then `reference` into one frame with the membership indicator,
  preserving a `.wf_source` marker (`"online"` / `"reference"`) and the original
  online row order.
- Records `method` (validated by `match.arg`; only `"logit"` is executable in
  0.6.0, `"rf"` / `"gbm"` abort in `wf_propensity()` as reserved), `by`
  (optional grouping column, present in both frames), and `id` (optional online
  id column; if `NULL`, online units are identified by row order).

Returns a `wf_target_propensity` object carrying: `$online`, `$reference`,
`$stacked` (with the membership indicator and `.wf_source`), `$membership` (LHS
name), `$predictors`, `$formula`, `$method`, `$by`, `$id`, and `$provenance`.
No model is fit at construction time — construction and execution are separated,
consistent with the package's precheck→execute discipline.

### `wf_propensity()`

`target` is a `wf_target_propensity` object. The online units it weights are
derived from the target (rows where the membership indicator is `1`), not
re-passed, so the online frame used for weighting cannot drift from the one used
to fit. `weight` selects the pseudo-weight form (`match.arg`; `"ipw"` only in 0.6.0,
`"kernel"` / `"matching"` reserved).
`stabilize` toggles stabilized IPW. `trim` optionally caps extreme weights.

Returns a `wf_weights` object (see Return Contract).

## Estimation Contract

For `method = "logit"`, `wf_propensity()` fits

```r
glm(membership ~ predictors, family = binomial, data = stacked)
```

on the stacked frame. When `by` is set, one model is fit per `by` group and the
groups are recombined; a group with no reference rows or no online rows raises
`wf_error_overlap`.

Let `p̂ᵢ` be the fitted membership probability (probability of being an online
unit given the covariates) for online unit `i`. Pseudo-design weights:

- `weight = "ipw"`, `stabilize = FALSE`: `wᵢ = 1 / p̂ᵢ`.
- `weight = "ipw"`, `stabilize = TRUE` (default): `wᵢ = π̄ / p̂ᵢ`, where `π̄` is
  the marginal online share `mean(membership)` (within the `by` group when `by`
  is set). Stabilization keeps the raw weights centered near 1 and tames their
  variance.
- `trim = c` (a positive scalar): after forming `wᵢ`, clamp to
  `min(wᵢ, c * median(w))` and count the number of trimmed units.

The final weights are normalized to **mean 1 within each `by` group** (a single
`.all` group when `by = NULL`). Because these weights are consumed as the
*initial* weights of a subsequent calibration that re-aligns margins, only the
relative weighting across units is load-bearing here; mean-1 normalization gives
a clean, interpretable `init_weight` and records the normalization in provenance.

Estimation rests on the standard non-probability composite-estimation framework
(Elliott & Valliant 2017): inverse-propensity pseudo-weighting corrects the
online sample's selection under the assumption that the model covariates capture
the selection mechanism. That assumption is surfaced in provenance and print
output, and the balance diagnostic is its operational check.

## Return Contract

`wf_propensity()` returns a `wf_weights` object so it feeds `init_weight` and
`wf_compose()` unchanged. Its `$data` frame contains, in online-row order:

- `id` — the online id (from `target$id`, else `as.character(seq_len(n))`).
- `group` — the `by` value as character, or `.all` when `by = NULL`.
- `weight` — the normalized pseudo-design weight.
- `feature` — `1 / weight`, matching the existing `wf_weights` convention.

`$provenance` records `method = "propensity"`, the fit `method` (`"logit"`),
`weight`, `stabilize`, `trim`, `by`, `id`, `predictors`, the surfaced
unbiasedness assumption, `created`, `elapsed`, and `package_version`.

Two diagnostic slots are attached, mirroring how `wf_poststrat()` attaches
`cell_report` / `collapse_map`:

- `$overlap` — a common-support report: per-source (online / reference)
  propensity min / quantiles / max, and a count of online units whose `p̂ᵢ`
  exceeds a boundary threshold (near-certain online membership → extreme
  weight). Poor overlap raises `wf_warning_quality` with the report in the
  condition `data`.
- `$balance` — a per-predictor table of standardized mean differences (SMD)
  between online and reference, computed **unweighted** and **pseudo-weighted**,
  so the analyst can see whether weighting shrank the covariate gaps. For a
  factor predictor, one row per non-reference level.

`print.wf_weights` already branches on `provenance$method`; a `"propensity"`
branch prints the unit/group counts, the fit and weight settings, the trimmed
count, and a one-line overlap verdict.

## Error Handling

All conditions use the existing `wf_abort` / `wf_warn` helpers and carry a
machine-readable `data` payload, extending the frozen taxonomy:

- `wf_error_input` — `formula` not a two-sided formula or has no RHS terms; a RHS
  variable missing from `online` or `reference`; LHS name collides with a
  predictor; `by` / `id` column absent; unsupported `method`
  (`"rf"` / `"gbm"` — reserved) or `weight` (`"kernel"` / `"matching"` —
  reserved); non-positive `trim`; empty `online` or `reference`.
- `wf_error_overlap` — a new subclass under `wf_error`: a `by` group missing an
  entire source, or (optionally reported) a factor level appearing in `online`
  but never in `reference`, making its propensity non-estimable.
- `wf_warning_quality` — poor common support (a configurable share of online
  units above the boundary threshold) or extreme untrimmed weights.

## Testing

Test-driven, `testthat` edition 3, one test file per function
(`test-target-propensity.R`, `test-propensity.R`):

- Constructor: two-sided formula validation; missing-RHS-variable error; LHS
  collision error; membership indicator built correctly (online = 1,
  reference = 0); `by` / `id` validation; stacked frame preserves online order.
- Fit: `glm` propensities strictly in (0, 1) on a constructed frame; `by`-group
  fitting recombines correctly; group missing a source raises
  `wf_error_overlap`.
- Weights: `ipw` equals `1 / p̂`; stabilized equals `π̄ / p̂`; `trim` clamps and
  counts hits; output normalized to mean 1 per group; `feature == 1 / weight`.
- Contract: output is a valid `wf_weights` that `wf_compose()` multiplies and
  that `wf_rake(init_weight = )` consumes without error.
- Overlap: boundary units counted; `wf_warning_quality` raised on a poor-support
  fixture.
- Balance: on a designed-bias fixture where a covariate is over-represented in
  online, the pseudo-weighted SMD is closer to 0 than the unweighted SMD.
- Reserved: `method = "rf"` / `"gbm"` and `weight = "kernel"` / `"matching"`
  abort with `wf_error_input`.
- Determinism: `glm` fit is reproducible across runs.

## Release Tasks

- Add `R/propensity.R` (both functions plus internal helpers) and roxygen docs.
- Export `wf_target_propensity`, `wf_propensity` in `NAMESPACE`; regenerate
  `man/`.
- Add the `"propensity"` branch to `print.wf_weights`.
- Bump `DESCRIPTION` to 0.6.0; add a `# weightflow 0.6.0` section to `NEWS.md`.
- Update `README.md` API list.
- `R CMD check` clean (no new hard dependencies; core stays base R).
```
