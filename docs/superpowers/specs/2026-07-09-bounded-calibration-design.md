# Bounded Calibration (GREG / logit) 0.8.0 Design

## Goal

Add a general calibration engine to `weightflow` so weights can be produced with
by-construction bounds (logit distance) — merging the current rake-then-trim
two-step into one — or as the linear GREG estimator. Both are reached through
`wf_calibrate(method = "greg" | "logit")`.

The feature follows `inst/design/weightflow_roadmap_design.md` Release 0.6
(bounded calibration), adapted to the current package sequence as version 0.8.0.
It lands on **Seam 2** (the method registry) from
`inst/design/weightflow_design.md`. Both methods consume the existing
`wf_target` categorical margins, are grouped per `by` like `wf_rake()`, and
return the standard `wf_weights`, so they compose with `wf_compose()` and run as
a `wf_replicates()` refit unchanged.

## Scope

Version 0.8.0 will implement:

- One Deville-Sarndal calibration engine with two distance functions:
  - `method = "greg"` — linear distance `F(u) = 1 + u` (unbounded).
  - `method = "logit"` — bounded distance keeping `w/d` within `bounds = c(L, U)`.
- Calibration to the existing `wf_target` categorical margins, grouped per `by`.
- `init_weight` support for base weights `d_i` (default all `1`).
- Complete-case handling via `na = c("drop", "error")`.
- Per-group convergence and adherence diagnostics.
- Dispatch through the existing `wf_calibrate()` (raking / poststrat routes
  unchanged).

Version 0.8.0 will **not** implement continuous auxiliary variables (no new
target constructor), a standalone `wf_greg()` export, `na = "fractional"` for
calibration (that expansion is specific to raking's IPF), `wf_auto_trim()`,
`wf_suggest_ladder()`, or `wf_report()`. Those remain later roadmap items.

## The Method

Calibration estimation (Deville & Sarndal 1992) finds weights
`w_i = d_i * F(x_i' lambda)` closest to base weights `d_i` under a distance
function, subject to the calibration constraints `sum_i w_i x_i = t`, where `x_i`
is the unit's auxiliary vector and `t` the population totals. The distance
function fixes `F` and its derivative `F'`:

- **greg (linear):** `F(u) = 1 + u`, `F'(u) = 1`. Weights `w_i = d_i (1 + x_i'
  lambda)` can go negative (unbounded). The calibration equation is linear, so
  `lambda` is one solve:
  `lambda = solve(sum_i d_i x_i x_i', t - sum_i d_i x_i)`.
- **logit (bounded):** with `A = (U - L) / ((1 - L) (U - 1))`,
  `F(u) = (L (U - 1) + U (1 - L) e^{A u}) / ((U - 1) + (1 - L) e^{A u})`.
  `F` maps the real line onto `(L, U)` with `F(0) = 1`, so `w_i / d_i` is
  strictly within `bounds` by construction. `lambda` is found by Newton
  iteration:
  `lambda <- lambda + solve(sum_i d_i F'(x_i' lambda) x_i x_i',
                            t - sum_i d_i F(x_i' lambda) x_i)`.

`bounds = c(L, U)` are on the weight ratio `w / d` — the same quantity trimming
caps — which is why logit calibration merges margin alignment and bounding into
one step.

## Constraints from `wf_target`

For each `by` group, the engine builds the auxiliary matrix `X` (one row per
complete-case unit) as:

- an intercept column of `1`s, whose target is the group total; plus
- one-hot indicator columns for each dim category, **dropping one reference
  level per dim** (the first level by the target's margin order).

The target vector `t` is `[total, margin counts for the retained levels...]`.
Dropping one level per dim removes the collinearity (each dim's indicators sum to
the intercept) that would make `sum_i d_i x_i x_i'` singular. Solving
`sum_i w_i x_i = t` reproduces every margin exactly: the dropped level follows
from the group total minus the retained levels. Each `by` group is calibrated
independently, mirroring `wf_rake()`'s group loop and reusing `.wf_group_keys()`.

## Public API

```r
wf_calibrate(
  sample, target,
  method = c("raking", "poststrat", "greg", "logit"),
  bounds = NULL,
  init_weight = NULL,
  na = c("drop", "error"),
  id = NULL,
  tol = 1e-8,
  max_iter = 100,
  precheck = TRUE,
  ...
)
```

- `method` — `"raking"` and `"poststrat"` route to the existing engines
  unchanged (their own defaults preserved). `"greg"` and `"logit"` route to the
  new calibration engine.
- `bounds` — required for `"logit"` as `c(L, U)` with `0 < L < 1 < U`; ignored
  for `"greg"` (which is unbounded).
- `init_weight` — column of base weights `d_i`; `NULL` means all `1`. Must be
  non-negative and finite.
- `na` — `"drop"` removes rows with `NA` in any calibration dim (with a
  `wf_warning_data`); `"error"` aborts. `"fractional"` is not supported by the
  calibration engine.
- `id` — optional unit id carried onto `wf_weights$data`.
- `tol`, `max_iter` — Newton convergence tolerance (max absolute margin residual
  relative to the group total) and iteration cap.
- `precheck` — run `wf_precheck()` first (default `TRUE`).

Only the extended `wf_calibrate()` is exported; the engine is internal
(`.wf_lincal*` helpers). A standalone `wf_greg()` is a trivial later addition if
wanted.

## Return Contract

`wf_calibrate(method = "greg" | "logit")` returns a `wf_weights` object:

- `$data` — `id`, `group`, `weight`, `feature = 1 / weight`, in sample row order
  (dropped rows excluded under `na = "drop"`).
- `$log` — one row per `by` group: `group`, `n`, `iterations`, `converged`,
  `max_resid` (max absolute achieved-minus-target margin, relative to total), and
  `ratio_min` / `ratio_max` (the realized `w / d` range; within `bounds` for
  logit).
- `$achieved` — calibrated margins per group and dim, like `wf_rake()`.
- `$provenance` — `method` (`"greg"` / `"logit"`), `distance`, `bounds`,
  `init_weight`, `na`, `tol`, `max_iter`, `by`, `created`, `elapsed`,
  `package_version`.

`print.wf_weights` gains a branch for `method %in% c("greg", "logit")` reporting
the distance, bounds (logit), weight range, and per-group convergence.

## Error Handling

Uses the existing `wf_abort` / `wf_warn` helpers with machine-readable `data`:

- `wf_error_input` — `method = "logit"` without `bounds`, or `bounds` not a
  two-element numeric with `0 < L < 1 < U`; non-positive `tol`; `max_iter` not a
  positive integer; `init_weight` negative or non-finite.
- `wf_error_schema` — `init_weight` column absent, or a calibration dim column
  absent.
- `wf_error_feasibility` — Newton fails to converge within `max_iter` for a
  group (bounds too tight to meet the margins), or the constraint system is
  singular (an empty retained category); the condition carries the group and the
  final residual.
- `wf_warning_data` — rows dropped under `na = "drop"`.

Precheck runs by default and surfaces sample/target incompatibilities before
execution, consistent with the package's precheck -> execute -> diagnose loop.

## Testing

Test-driven, `testthat` edition 3, in `tests/testthat/test-calibrate-linear.R`:

- **GREG closed form:** on a hand-constructed single-group, two-category problem,
  the linear weights match the analytic `lambda` solution.
- **GREG hits margins:** achieved margins equal target margins to tolerance;
  weights can differ from raking (different distance) but calibrate correctly.
- **Logit bounds:** with `bounds = c(L, U)`, every `w_i / d_i` lies strictly in
  `(L, U)` while achieved margins still match the target.
- **Logit infeasibility:** bounds tight enough that no in-bounds weights meet the
  margins raise `wf_error_feasibility`.
- **Logit ~ raking limit:** with very loose bounds, logit weights approximate the
  raking-ratio (multiplicative) solution within tolerance.
- **init_weight:** weights are proportional to `base * F(x' lambda)`; a
  non-uniform base shifts weights and margins still match.
- **Grouping:** two `by` groups are calibrated independently to their own
  margins.
- **Validation:** `method = "logit"` without `bounds`, malformed `bounds`,
  missing `init_weight` column, and `na = "error"` on data with `NA` each raise
  the mapped condition; `na = "drop"` warns.
- **Contract:** the result composes via `wf_compose()` and serves as a
  `wf_replicates()` refit; `wf_calibrate(method = "raking" | "poststrat")` still
  routes to the existing engines.

## Release Tasks

- Add `R/calibrate-linear.R` (distance functions, per-group solver, orchestration)
  with roxygen docs; extend `R/calibrate.R` dispatch; add the print branch in
  `R/rake.R`.
- Regenerate `man/`; `wf_calibrate` doc gains `bounds` / `init_weight` / `na` etc.
- Bump `DESCRIPTION` to 0.8.0; add a `# weightflow 0.8.0` section to `NEWS.md`.
- Add a "Bounded Calibration" section and function-reference note to `README.md`.
- `R CMD check` clean (no new hard dependencies; core stays base R).
```
