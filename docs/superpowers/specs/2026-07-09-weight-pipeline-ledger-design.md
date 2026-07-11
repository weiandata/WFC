# Weight Pipeline Ledger 0.4.0 Design

## Goal

Add the first production-weighting pipeline layer to `weightflow` by introducing
`wf_compose()`, a public API for chaining multiple `wf_weights` stages into one
auditable `wf_weights` result.

The feature follows `inst/design/weightflow_design.md` Seam 3: weighting stages
such as design weighting, nonresponse adjustment, and calibration should be
inspectable as a pipeline rather than flattened into an undocumented final
vector.

## Scope

Version 0.4.0 will implement the ledger foundation only:

- Add `wf_compose()` for multiplying compatible `wf_weights` stages.
- Preserve stage-level provenance in the composed output.
- Keep the composed result compatible with `print.wf_weights()` and
  `wf_diagnose()`.
- Document and test the row matching, group consistency, normalization, and
  provenance contracts.

Version 0.4.0 will not implement `wf_blend()`, replicate weights, propensity
adjustment, nonresponse modeling, linear/logit calibration, or a method registry.
Those remain future consumers of the ledger.

## Public API

```r
wf_compose(..., id = NULL, normalize = c("none", "mean1", "sum"))
```

`...` accepts two or more `wf_weights` objects. Each object must include
`data$id`, `data$group`, and `data$weight`.

The output is a `wf_weights` object with:

- `data$id`: matched unit identifiers.
- `data$group`: group assignment from the first stage.
- `data$weight`: product of all stage weights after optional normalization.
- `data$feature`: `1 / weight`.
- `log`: one row per output group with simple composition diagnostics.
- `achieved`: `NULL`, because composition does not itself calibrate margins.
- `provenance$method`: `"compose"`.
- `provenance$stages`: ordered list of input stage provenance records.
- `provenance$compose`: composition settings and stage summaries.

The output remains classed only as `wf_weights` for compatibility with existing
printing and diagnostics. A future subclass can be added if a separate print
method becomes necessary, but 0.4.0 should not add that surface area.

## Row Matching Contract

Composition is identity-safe by default:

- If `id` is supplied, each stage is matched by that column in `stage$data`.
- If `id` is `NULL`, `wf_compose()` uses `data$id` when every stage has an `id`
  column.
- Row-order composition is allowed only when no input has an `id` column and all
  stages have the same row count. In that case synthetic IDs are generated from
  row numbers.

Every matched stage must contain exactly the same IDs. Missing, extra, duplicate,
or `NA` IDs fail with class `wf_error_input`. Silent recycling, partial joins,
and intersection-only composition are not allowed.

## Group Contract

The first stage defines the output group for each ID. Later stages must contain a
`group` column and must assign the same group to the same ID. A mismatch fails
with class `wf_error_input` and includes the first mismatched IDs in the
condition payload.

This strict contract prevents a final weight from blending incompatible group
semantics. It also keeps `wf_diagnose()` behavior predictable because diagnostics
split by `w$data$group`.

## Normalization

The default is `normalize = "none"` so the final weight is the mathematical
product of the input stages.

Two optional normalizations are included because they are common production
needs and do not change the core contract:

- `"mean1"` rescales the composed weights so their mean is 1.
- `"sum"` rescales the composed weights so their sum equals the sum of the first
  stage's weights.

Normalization is recorded in `provenance$compose`.

## Provenance

Composition must make the pipeline inspectable:

- `provenance$method` is `"compose"`.
- `provenance$stages` is an ordered list with one entry per input stage.
- Each stage entry records the original stage provenance, row count, group count,
  total weight, mean weight, minimum weight, and maximum weight.
- `provenance$compose` records `normalize`, `stage_count`, `created`, `elapsed`,
  and `package_version`.

The composed object should not mutate or remove provenance from input objects.

## Errors and Warnings

`wf_compose()` must use existing classed conditions:

- Non-`wf_weights` input: `wf_error_input`.
- Fewer than two stages: `wf_error_input`.
- Missing required columns: `wf_error_schema`.
- Duplicate or missing IDs: `wf_error_input`.
- Different ID sets: `wf_error_input`.
- Group mismatch across stages: `wf_error_input`.
- Non-finite, zero, or negative weights: `wf_error_input`.
- Unknown normalization mode: `wf_error_input`.

Composition should not warn for ordinary weight variation. Diagnostics are
already handled by `wf_diagnose()`.

## Testing Strategy

Tests will be written before implementation and should cover:

- Two `wf_weights` objects compose by ID and multiply weights correctly.
- Matching by ID is invariant to input row order.
- Duplicate IDs fail.
- Missing IDs fail.
- Different ID sets fail.
- Incompatible group assignments fail.
- Non-positive or non-finite weights fail.
- `normalize = "mean1"` sets the final mean weight to 1.
- `normalize = "sum"` preserves the first stage's total weight.
- The composed object works with `wf_diagnose()`.
- Provenance contains all stage records in order.

Existing raking, post-stratification, target, collapse, and data-policy tests
must remain green.

## Documentation and Release Updates

The implementation will update:

- `DESCRIPTION` version to `0.4.0`.
- `NAMESPACE` and `man/*.Rd` through roxygen2.
- `README.md` with a short pipeline example.
- `NEWS.md` with the 0.4.0 entry.

The repository language policy remains unchanged: package code, tests,
documentation, configuration, and commit messages are English-only, with
`README.zh-CN.md` as the only Chinese-language repository file.

The private-data policy remains unchanged: no `private-data/`, spreadsheets,
RData files, package check directories, or tarballs may be tracked or included
in the package build.

## Acceptance Criteria

- `wf_compose()` is exported and documented.
- Composed weights are correct under ID matching and normalization.
- Unsafe composition fails with classed errors.
- The composed result is a valid `wf_weights` object accepted by
  `wf_diagnose()`.
- Stage provenance is retained in order.
- Full `devtools::test()` passes.
- `R CMD build .` and `R CMD check --no-manual weightflow_0.4.0.tar.gz` pass,
  allowing only repository-index warnings caused by restricted network access.
- Language and private-data audits produce no tracked-policy violations.
