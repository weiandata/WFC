# Dual-Source Fusion 0.5.0 Design

## Goal

Add estimator-level dual-source fusion to `weightflow` by introducing
`wf_blend()`, a public API for combining online and offline calibrated estimates
without pooling row-level weights.

The feature follows `inst/design/weightflow_roadmap_design.md` Release 0.3
dual-source fusion, adapted to the current package sequence as version 0.5.0.
It lands on Seam 3 from `inst/design/weightflow_design.md`: the weight pipeline
ledger. `wf_compose()` now records chained weighting stages; `wf_blend()` will
record how two calibrated sources are fused into one reported estimate.

## Scope

Version 0.5.0 will implement the first production-ready fusion layer:

- Add `wf_blend()` for fusing two `wf_weights` objects.
- Compute each source's estimate within a cell before combining sources.
- Support cell-level or group-level lambda application.
- Support `"neff"`, `"inverse_variance"`, and `"fixed"` lambda strategies.
- Return a `wf_blend_result` object with estimates, lambda diagnostics, source
  diagnostics, sensitivity output, and provenance.
- Document that fusion is estimator-level and must not be implemented by
  stacking online and offline weighted rows.

Version 0.5.0 will not implement replicate-weight variance, propensity
correction, MRP, model-based bias correction, or unit-level fused weights. Those
remain later roadmap items.

## Public API

```r
wf_blend(
  online,
  offline,
  by_cell,
  lambda = c("neff", "inverse_variance", "fixed"),
  lambda_fixed = NULL,
  outcome = NULL,
  level = c("cell", "group"),
  trim_lambda = c(0.05, 0.95),
  sensitivity = TRUE
)
```

`online` and `offline` must be `wf_weights` objects. Their `$data` frames must
contain `group`, `weight`, and the columns named in `by_cell`. If `outcome` is
not `NULL`, both `$data` frames must also contain the named numeric outcome
column. This keeps `wf_rake()` and `wf_poststrat()` from retaining full source
records by default; callers can join analysis columns onto `weights$data` when
they need fusion.

`by_cell` defines the fusion cells. Cells are always evaluated within `group`, so
the effective cell key is `group + by_cell`.

`outcome` controls the output mode:

- If `outcome` is a numeric column name, `wf_blend()` returns fused estimates.
- If `outcome = NULL`, `wf_blend()` returns a cell-level fusion ledger with
  source weight totals and applied lambda, but it does not create pooled
  unit-level weights.

## Estimation Contract

For each source and each `group + by_cell` cell, `wf_blend()` computes:

- Weighted estimate: `sum(weight * outcome) / sum(weight)`.
- Effective sample size: `sum(weight)^2 / sum(weight^2)`.
- Approximate estimator variance:
  `sum(weight^2 * (outcome - estimate)^2) / sum(weight)^2`.
- Source support diagnostics: row count, weight sum, missing outcome count, and
  whether the cell is estimable.

The fused estimate is:

```r
estimate = lambda * estimate_online + (1 - lambda) * estimate_offline
```

This formula is the central rule of the feature. `wf_blend()` must never combine
online and offline sources by stacking rows and recomputing one weighted mean.

## Lambda Strategies

`lambda = "neff"` computes:

```r
lambda = neff_online / (neff_online + neff_offline)
```

`lambda = "inverse_variance"` computes:

```r
lambda = variance_offline / (variance_online + variance_offline)
```

This is the minimum-variance convex combination when both source estimates are
approximately unbiased.

`lambda = "fixed"` uses user-supplied values from `lambda_fixed`. A scalar fixed
lambda applies everywhere. A data frame fixed lambda must include a `lambda`
column and key columns matching the requested `level`: `group` for
`level = "group"`, or `group + by_cell` for `level = "cell"`.

Data-driven lambdas are clamped by `trim_lambda` only when both sources have
valid support. Degenerate one-source cells bypass trimming and collapse to
lambda `1` or `0`, because the alternative source cannot estimate the cell.

Fixed lambdas are validated to be finite values in `[0, 1]` and are not trimmed.
They are compared with the neff lambda in diagnostics so a manual prior is
visible rather than silently treated as optimal.

## Level Contract

`level = "cell"` computes and applies lambda independently for every
`group + by_cell` cell.

`level = "group"` computes one lambda per `group`, then applies that group-level
lambda to every cell in the group. Cell-level source estimates are still
computed before fusion. This option is useful when cells are too sparse for
stable cell-specific lambdas but the analyst still wants per-cell output.

## Result Object

`wf_blend()` returns an object with class `wf_blend_result`.

For `outcome != NULL`, the result contains:

- `estimates`: one row per fused cell with `group`, `by_cell`, source estimates,
  source variances, source effective sample sizes, applied lambda, fused
  estimate, and approximate fused variance.
- `summary`: group-level and overall weighted summaries derived from the cell
  estimates.
- `lambda`: the effective lambda table actually applied.
- `diagnostics`: source support, missing outcome counts, degenerate cells,
  lambda trim counts, and fixed-lambda comparison diagnostics when applicable.
- `sensitivity`: optional sweep output when `sensitivity = TRUE`.
- `provenance`: method, source provenance, `by_cell`, `outcome`, lambda strategy,
  level, trim settings, created timestamp, elapsed time, assumptions, and
  package version.

For `outcome = NULL`, the result contains:

- `cell_weights`: one row per fused cell with source weight totals, support
  counts, applied lambda, and fused cell total.
- `lambda`, `diagnostics`, and `provenance` using the same contracts.

The result is not a `wf_weights` object. It represents fused estimates or a
cell-level ledger, not respondent-level calibrated weights.

## Sensitivity Output

When `sensitivity = TRUE`, `wf_blend()` computes a simple global online-share
sweep over `seq(0.3, 0.9, by = 0.1)`. The sweep reuses source cell estimates and
reports group-level and overall fused estimates under each fixed global lambda.

Sensitivity output is diagnostic only. It does not replace the effective lambda
used in `estimates`.

## Assumptions and Provenance

The result provenance must explicitly record the assumptions from the roadmap:

- Convex fusion is meaningful only if both source estimates are approximately
  unbiased for the cell quantity.
- The online source is treated as approximately unbiased only to the extent that
  calibration variables explain the selection mechanism.
- Sensitivity output is provided to expose dependence on lambda choices.

Source provenance from both `wf_weights` inputs must be retained without
mutation.

## Errors and Warnings

`wf_blend()` must use existing classed conditions:

- Non-`wf_weights` input: `wf_error_input`.
- Missing `$data`, `group`, `weight`, `by_cell`, or `outcome` columns:
  `wf_error_schema`.
- Non-finite, missing, or negative weights: `wf_error_input`.
- Non-numeric or all-missing outcome when `outcome` is supplied:
  `wf_error_input`.
- Unknown lambda strategy or level: `wf_error_input`.
- Invalid `trim_lambda`: `wf_error_input`.
- Missing or malformed `lambda_fixed` for `lambda = "fixed"`:
  `wf_error_input`.
- Duplicate fixed-lambda keys: `wf_error_input`.
- Cells with no estimable source: `wf_error_feasibility`.

Warnings should be classed:

- One-source cells: `wf_warning_quality`.
- Trimmed data-driven lambda values: `wf_warning_quality`.
- Fixed lambdas materially different from neff lambdas: `wf_warning_quality`.

## Testing Strategy

Tests will be written before implementation and should cover:

- `wf_blend()` rejects non-`wf_weights` inputs.
- Required columns are validated with classed errors.
- Weighted source estimates are computed before fusion.
- Stacking rows would give a different answer in a constructed case, and
  `wf_blend()` returns the estimator-level answer.
- `lambda = "neff"` uses source effective sample sizes.
- `lambda = "inverse_variance"` uses source variances.
- Scalar `lambda_fixed` applies everywhere.
- Data frame `lambda_fixed` applies by group and by cell.
- Data-driven lambda trimming works when both sources have support.
- One-source cells collapse to lambda `1` or `0` without trimming.
- `level = "group"` computes one lambda per group but returns cell estimates.
- `outcome = NULL` returns a cell-level ledger, not `wf_weights`.
- Provenance retains both source provenance records.
- Sensitivity output is present when requested and absent when disabled.
- Print method summarizes estimates, lambda range, and warnings count.

Existing raking, post-stratification, foundation API, composition, target,
collapse, and data-policy tests must remain green.

## Documentation and Release Updates

The implementation will update:

- `DESCRIPTION` version to `0.5.0`.
- `NAMESPACE` and `man/*.Rd` through roxygen2.
- `README.md` with a short dual-source fusion example.
- `NEWS.md` with the 0.5.0 entry.

The repository language policy remains unchanged: package code, tests,
documentation, configuration, and commit messages are English-only, with
`README.zh-CN.md` as the only Chinese-language repository file.

The private-data policy remains unchanged: no `private-data/`, spreadsheets,
RData files, package check directories, or tarballs may be tracked or included
in the package build.

## Acceptance Criteria

- `wf_blend()` is exported and documented.
- Fusion is estimator-level, not row-stacking.
- `neff`, `inverse_variance`, and `fixed` lambda strategies are implemented.
- Applied lambda is inspectable per cell or group.
- Degenerate source support is explicit in diagnostics.
- The result carries source estimates, fused estimates, variance approximations,
  lambda diagnostics, sensitivity output, and provenance.
- Full `devtools::test()` passes.
- `R CMD build .` and `R CMD check --no-manual weightflow_0.5.0.tar.gz` pass,
  allowing only repository-index warnings caused by restricted network access.
- Language and private-data audits produce no tracked-policy violations.
