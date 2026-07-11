# Variance & Uncertainty 0.7.0 Design

## Goal

Add replicate-weight variance estimation to `weightflow` so any weighted figure
can carry a standard error and confidence interval that reflect **calibration
uncertainty**, not just raw sampling. Introduces `wf_replicates()` and
`wf_variance()`, plus a small enabling change to `wf_rake()`.

The feature follows `inst/design/weightflow_roadmap_design.md` Release 0.5
(variance and uncertainty), adapted to the current package sequence as version
0.7.0. It lands on **Seam 3** (the weight pipeline) from
`inst/design/weightflow_design.md`. A replicate is the calibration pipeline
re-executed on perturbed base weights, so the resulting variance captures the
uncertainty of the calibration step itself — the omission the roadmap flags as
"common and serious."

## Scope

Version 0.7.0 will implement:

- `wf_rake(init_weight = )` — an enabling change so raking pipelines can consume
  replicate base weights (the `wf_poststrat()` / `wf_propensity()` seam extended
  to raking).
- `wf_replicates()` — generate re-calibrated replicate weights via bootstrap,
  jackknife, or BRR, driven by a user refit closure.
- `wf_variance()` — combine replicate weights and an estimator into an estimate,
  variance, standard error, and confidence interval.
- A single unified variance-combining rule shared by all three methods.

Version 0.7.0 will **not** implement Fay's BRR (`rho`), parallel replication
(`parallel = TRUE` is reserved and documented), an Rcpp kernel, analytic
(non-replicate) variance, or a re-executable `wf_compose` recipe object. The
refit closure is the replay mechanism; those remain later work.

## Architecture: one unified combining rule

All three methods reduce to the survey-standard combining form:

```
Var(theta_hat) = scale * sum_r rscales_r * (theta_hat_r - theta_hat)^2
```

where `theta_hat` is the full-sample estimate and `theta_hat_r` the estimate
under replicate `r`. The three generators differ only in how they build
replicate base-weight multipliers and what `(scale, rscales)` they emit;
`wf_variance()` is method-agnostic and consumes those stored values. This keeps
the code from forking three ways and makes the variance step trivial to extend
(e.g. Fay's BRR later just changes `rscales`).

**Files:**

- `R/replicates.R` — the three multiplier generators, `wf_replicates()`, the
  `wf_replicate_weights` constructor and `print` method.
- `R/variance.R` — `wf_variance()`, the `wf_variance_result` object, its `print`
  and `as.data.frame` methods.
- `R/rake.R` — targeted edit adding `init_weight` to `wf_rake()`.

## Enabling change: `wf_rake(init_weight = NULL)`

Raking's IPF currently starts every group from a uniform `w0 = total / n`.
Because IPF is scale-invariant to a constant starting point, the change is safe:
start from `w0 = base_w * (init_i / mean(init))` per group, where `init_i` is the
per-row initial weight and `base_w = total / n`.

- When `init_weight = NULL`, the relative factor is `1` for every row, so `w0` is
  unchanged and results are byte-identical to the current behaviour (guarded by
  the existing raking tests).
- When `init_weight` names a column, the relative factor injects the base-weight
  structure while preserving the group-total scale; IPF then calibrates to the
  margins as before. For fractional-NA-expanded rows, the relative factor
  multiplies the existing share.

`init_weight` is a single column name in `sample`; a missing column raises
`wf_error_schema` (consistent with the existing precheck/extract validation).

## Public API

```r
wf_replicates(
  data,
  refit,
  method = c("bootstrap", "jackknife", "brr"),
  R = 500,
  strata = NULL,
  clusters = NULL,
  id = NULL,
  base_weight = NULL,
  seed = NULL
)

wf_variance(
  replicates,
  estimator,
  data,
  level = 0.95,
  ci = c("normal", "percentile")
)
```

### `wf_replicates()`

- `data` — the input data frame (one row per unit).
- `refit` — a closure `function(data, weights) -> wf_weights`. It re-runs the
  calibration pipeline using `weights` as the base/initial weights and returns a
  `wf_weights` object. The user writes it around their existing
  `wf_rake()` / `wf_poststrat()` / `wf_propensity()` chain (each stage now
  consumes the base weights through its `init_weight` slot).
- `method` — replication method (`match.arg`).
- `R` — number of bootstrap replicates. Ignored for jackknife and BRR, which
  derive their own replicate count from the design.
- `strata`, `clusters` — column names in `data` defining the design. A cluster
  is the primary sampling unit (PSU); when `clusters = NULL` each row is its own
  PSU; when `strata = NULL` there is a single stratum.
- `id` — id column used to align each replicate's calibrated weights back to the
  canonical unit order. When `NULL`, row order is used and `refit` must preserve
  it.
- `base_weight` — column of starting base weights; when `NULL`, all `1`.
- `seed` — integer seed stored in provenance; set before bootstrap draws for
  reproducibility. Ignored (recorded as `NULL`) for the deterministic methods.

The full-sample calibrated weights come from `refit(data, base)`. For each
replicate `r`, the generator builds a multiplier vector `mult_r` over units, and
the replicate calibrated weights come from `refit(data, base * mult_r)`, aligned
by `id`. If `refit` returns a `wf_weights` whose ids do not match the canonical
set (missing, extra, or reordered beyond recovery), `wf_replicates()` raises
`wf_error_input`.

Returns a `wf_replicate_weights` object:

- `$base` — data frame `id`, `group`, `weight` (full-sample calibrated).
- `$replicates` — an `n_units x R` numeric matrix of calibrated replicate
  weights, columns in replicate order, rows in canonical id order.
- `$scale` — scalar combining factor.
- `$rscales` — numeric length-`R` per-replicate factor.
- `$method`, `$design` (strata/cluster metadata, replicate count), and
  `$provenance` (`method`, `R`, `seed`, `strata`, `clusters`, `created`,
  `elapsed`, `package_version`).

### Generators

- **bootstrap** — Rao-Wu rescaled bootstrap. Within each stratum with `n_h` PSUs,
  resample `n_h - 1` PSUs with replacement; the multiplier for PSU `i` is
  `(n_h / (n_h - 1)) * t_hi` where `t_hi` is its resample count. Units inherit
  their PSU's multiplier. Strata with `n_h = 1` keep multiplier `1`.
  `scale = 1 / R`, `rscales = rep(1, R)`.
- **jackknife** — stratified delete-one-PSU (JKn). One replicate per PSU: the
  deleted PSU's units get multiplier `0`; the remaining units in its stratum are
  rescaled by `n_h / (n_h - 1)`; units in other strata keep `1`. Replicate count
  `R = sum_h n_h`. `scale = 1`, `rscales_r = (n_h - 1) / n_h` for the replicate
  deleting a PSU in stratum `h`. Strata with `n_h = 1` contribute no replicate
  (they cannot be jackknifed) and raise `wf_warning_quality`.
- **brr** — Balanced Repeated Replication, standard half-sampling. Requires
  exactly 2 PSUs per stratum. `R` is the smallest power of two `>= H + 1` (`H` =
  number of strata) via a Sylvester-Hadamard matrix; per replicate and stratum,
  the Hadamard sign selects one PSU to get multiplier `2` and the other `0`.
  `scale = 1 / R`, `rscales = rep(1, R)`.

### `wf_variance()`

- `replicates` — a `wf_replicate_weights` object.
- `estimator` — a closure `function(weights, data) -> numeric`. Returns a scalar
  or a named vector (one entry per reported quantity, e.g. a rate per subgroup).
  Its length must be constant across the base and all replicate calls.
- `data` — the data frame the estimator reads (aligned to the replicate rows).
- `level` — confidence level in `(0, 1)`.
- `ci` — `"normal"` (`theta_hat +/- z * se`) or `"percentile"` (replicate
  quantiles). `"percentile"` is valid only for `method = "bootstrap"`; requesting
  it otherwise raises `wf_error_input`.

Computes `theta_hat` from the full-sample calibrated weights (`$base$weight`),
`theta_hat_r` from each replicate column, then `Var`, `se = sqrt(Var)`, and the
CI per quantity. Returns
a `wf_variance_result`: one row per quantity with `quantity`, `estimate`,
`variance`, `se`, `ci_lower`, `ci_upper`, plus `provenance` (method, level, ci,
R). It has `print()` and `as.data.frame()` methods.

## Error Handling

Uses the existing `wf_abort` / `wf_warn` helpers with machine-readable `data`,
extending the frozen taxonomy:

- `wf_error_input` — `refit` / `estimator` not functions; invalid `method` /
  `ci`; `R` not a positive integer (bootstrap); `level` not in `(0, 1)`; missing
  `strata` / `clusters` / `id` / `base_weight` columns; `percentile` CI for a
  non-bootstrap method; estimator or refit output of inconsistent length; refit
  returning a mismatched id set.
- `wf_error_design` — a new subclass under `wf_error`: clusters not nested within
  strata (a cluster spanning two strata), or a BRR stratum without exactly 2
  PSUs.
- `wf_error_schema` — `init_weight` column absent in `wf_rake()`.
- `wf_warning_quality` — a stratum with a single PSU under jackknife (cannot be
  jackknifed; contributes no replicate).

## Testing

Test-driven, `testthat` edition 3:

- `test-rake-init-weight.R` — `init_weight = NULL` reproduces current raking
  results exactly; a non-uniform `init_weight` shifts weights in the expected
  direction while margins still match; a missing column raises `wf_error_schema`.
- `test-replicates.R` — bootstrap multipliers average about `1` per stratum and
  respect cluster membership; jackknife deletes exactly one PSU per replicate
  with the correct `n_h/(n_h-1)` rescale and emits `R = sum n_h`; BRR builds a
  `2`-PSU design, its Hadamard matrix is orthogonal, and a non-`2`-PSU stratum
  raises `wf_error_design`; clusters spanning strata raise `wf_error_design`;
  `seed` makes bootstrap reproducible; the refit closure is invoked with the
  perturbed base weights and its output is aligned by id.
- `test-variance.R` — the unified formula reproduces a hand-computed variance on
  a tiny fixture for each method; a weighted-mean sanity check where the
  replicate SE matches the analytic SE within tolerance; vector (subgroup)
  estimators return one row per quantity; `normal` and `percentile` CIs; a
  `percentile` request on a jackknife result raises `wf_error_input`;
  `as.data.frame()` round-trips.

## Release Tasks

- Add `R/replicates.R` and `R/variance.R` with roxygen docs; edit `R/rake.R`.
- Export `wf_replicates`, `wf_variance` in `NAMESPACE`; regenerate `man/`.
- Bump `DESCRIPTION` to 0.7.0; add a `# weightflow 0.7.0` section to `NEWS.md`.
- Add a "Variance & Uncertainty" section and function-reference rows to
  `README.md`.
- `R CMD check` clean (no new hard dependencies; core stays base R).
```
