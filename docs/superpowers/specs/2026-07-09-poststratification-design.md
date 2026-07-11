# Post-Stratification 0.2.0 Design

## Goal

Add the 0.2.0 single-source post-stratification workflow described in
`inst/design/weightflow_poststrat_design.md`, using
`inst/reference/weightflow_poststrat.R` as the algorithmic reference and the
existing 0.1 package objects as the compatibility boundary.

## Scope

This release adds cell-level post-stratification only. It does not add source
blending, replicate weights, parallel execution, or a public calibration-method
registry. Those remain reserved extension seams from the main design document.

The public API additions are:

- `wf_target_population(..., keep_joint = FALSE)`, with `FALSE` preserving 0.1
  behavior and `TRUE` storing a per-group joint population cell table.
- `wf_collapse_ladder()` for ordered, cumulative, explicit category collapse
  ladders.
- `wf_plan_poststrat()` for pre-execution cell resolution and audit review.
- `wf_poststrat()` for calibration-style post-stratification.
- `print.wf_poststrat_plan()` and `summary.wf_poststrat_plan()` reporting
  helpers.

## Compatibility

All existing 0.1 exports, classes, tests, and examples must continue to work.
The `wf_target` object gains one optional field, `joint`, only when requested by
`keep_joint = TRUE`. Existing raking code must ignore that field.

`wf_poststrat()` returns the existing `wf_weights` class so that
`wf_diagnose()` can consume post-stratified weights without a new diagnostic
object. The result adds `cell_report` and `collapse_map` fields for audit use.

## Behavior

Post-stratification uses calibration-style weighting:

```r
final_weight_i = init_weight_i * population_cell_total / sum(init_weight_in_cell)
```

When `init_weight = NULL`, all initial weights are one, which reduces to classic
cell post-stratification.

The target must contain joint cells. If the target was built without
`keep_joint = TRUE`, `wf_poststrat()` and `wf_plan_poststrat()` raise
`wf_error_schema` with instructions to rebuild the target.

Sparse cells are resolved through the user-declared ladder. Adaptive resolution
is attempted first; if it cannot form a valid supported partition, the group
falls back to a single province-uniform ladder level. Empty population-positive
cells are handled by `empty_cell = "redistribute"`, `"flag"`, or `"error"`.

Every run enforces the group total constraint and reports realized totals in
the result log. Any unexpected total mismatch is `wf_error_internal`.

## Implementation Notes

The reference implementation is not copied blindly. The package implementation
must preserve its core algorithms while completing package integration:

- roxygen comments and generated `.Rd` files for exported functions.
- `NAMESPACE` exports and S3 registrations.
- testthat coverage for red-green TDD cycles.
- audit fields for orphan redistribution and resolved-cell mappings.
- 0.1 regression coverage for raking behavior after the `wf_target` addition.

All implementation remains base R with no hard imports.

## Verification

Minimum verification before completion:

- focused post-stratification tests pass,
- full `devtools::test()` passes,
- documentation is regenerated,
- `R CMD build .` succeeds,
- `R CMD check --no-manual` on the built tarball exits with status OK,
- repository audit shows no private data, build outputs, or non-English files
  were staged.
