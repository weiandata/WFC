# Foundation API Completion 0.3.0 Design

## Goal

Complete the foundation APIs promised in `inst/design/weightflow_design.md`
without expanding into weight blending, replicate weights, parallel execution,
or release infrastructure. This version makes the package easier to use in real
workflows by adding manual targets, target shrinkage, explicit collapse
suggestions, and one unified calibration entry point.

## Scope

The 0.3.0 scope is limited to five additive changes:

- `wf_target_manual()` constructs a canonical `wf_target` from a ready-made
  margins table.
- `wf_target_shrink()` shrinks each group target toward a reference target while
  preserving each group's total.
- `wf_suggest_collapse()` converts selected `wf_precheck()` findings into
  reviewable `wf_collapse_plan` objects using only user-declared collapse
  ladders.
- `wf_apply_collapse()` accepts both the existing simple `list(dim, map)` input
  and new `wf_collapse_plan` objects.
- `wf_calibrate()` dispatches to existing engines with `method = "raking"` or
  `method = "poststrat"`.

No existing public API is removed or renamed. The current `wf_rake()` and
`wf_poststrat()` functions remain direct, documented entry points.

## Non-Goals

This release does not implement:

- `wf_compose()` or `wf_blend()`;
- replicate weights;
- linear, logit, propensity, or MRP methods;
- parallel execution;
- plot methods, vignettes, GitHub Actions, or CRAN submission work;
- automatic category merging that invents rules not declared by the user.

## API Design

### `wf_target_manual()`

`wf_target_manual()` accepts a long margins table with one row per
`group x dimension x category` margin.

Proposed signature:

```r
wf_target_manual(
  margins,
  dims,
  dim_col = "dimension",
  cat_col = "category",
  value_col = "value",
  by = NULL,
  group_col = by,
  totals = NULL,
  mode = "manual"
)
```

When `by = NULL`, the constructor builds a single `_all_` group. When `by` is
provided, `group_col` identifies the group key column in `margins`. Category
keys are normalized with the existing `.chr()` helper. For each group and
dimension, margin values must be finite and non-negative, and each dimension's
sum must equal the group total. If `totals` is `NULL`, the constructor infers
the group total from the first dimension and then requires every other
dimension to match it. If `totals` is supplied, it is treated as the authority.

The result is a normal `wf_target` with `mode = "manual"` and no `joint` field.
It can be consumed by `wf_precheck()`, `wf_rake()`, and `wf_calibrate(method =
"raking")`. It cannot be used by `wf_poststrat()` unless a future API supplies
joint cells.

### `wf_target_shrink()`

`wf_target_shrink()` blends each group target's category proportions toward a
reference target's category proportions while preserving the group's total.

Proposed signature:

```r
wf_target_shrink(target, reference, lambda, groups = NULL)
```

`lambda` is the local-target weight in `[0, 1]`: `1` returns the original
target, `0` returns the reference proportions rescaled to each local group
total. `reference` may be a single-group target or a grouped target with
matching group names. `groups = NULL` shrinks all target groups.

For every selected group and dimension:

```r
new_share = lambda * local_share + (1 - lambda) * reference_share
new_margin = target_group_total * new_share
```

The function requires identical dimensions and compatible category sets. It
records `target$meta$shrinkage` with the lambda value, reference mode, affected
groups, and timestamp.

### `wf_suggest_collapse()`

`wf_suggest_collapse()` turns precheck findings into explicit suggestions. It
does not edit data.

Proposed signature:

```r
wf_suggest_collapse(
  precheck,
  dims,
  checks = c("cat_infeasible", "support_thin", "risk_extreme_ratio"),
  max_steps = 1
)
```

The function examines `precheck$issues` for selected checks. For each affected
dimension, it looks up `dims$collapse[[dimension]]` and selects the first
available ladder step that maps the affected category. Suggestions are returned
as a `wf_collapse_plan` object:

```r
structure(list(
  actions = data.frame(group, dim, category, check, step, stringsAsFactors = FALSE),
  maps = list(list(dim = "edu5", map = c("1" = "12", "2" = "12"))),
  source_checks = issues_subset,
  created = Sys.time()
), class = "wf_collapse_plan")
```

If no declared ladder can address an issue, the plan records the unresolved
issue in `unresolved` rather than guessing. This preserves the design principle
that category merges must be explicit and reviewable.

### `wf_apply_collapse()`

`wf_apply_collapse()` keeps its current behavior for a simple `list(dim, map)`.
For `wf_collapse_plan`, it applies the plan maps sequentially to both the sample
and target, validates target invariants after each map, and appends the applied
plan to `target$meta$collapsed`.

For a grouped suggestion, the first implementation applies maps globally within
the dimension rather than mutating only one group. This matches the current
target structure and keeps sample recoding consistent. The plan still records
the issue group for audit.

### `wf_calibrate()`

`wf_calibrate()` is a small dispatch layer over existing engines.

Proposed signature:

```r
wf_calibrate(sample, target, method = c("raking", "poststrat"), ...)
```

Behavior:

- `method = "raking"` calls `wf_rake(sample, target, ...)`.
- `method = "poststrat"` calls `wf_poststrat(sample, target, ...)`.
- Unknown methods raise `wf_error_input`.

The implementation may use a small internal registry, but it should not expose
an extension system until additional methods exist.

## Compatibility

All current tests for 0.2.0 must continue to pass. Existing workflows that call
`wf_rake()`, `wf_poststrat()`, `wf_precheck()`, and `wf_apply_collapse()` with a
simple list must behave the same.

New targets returned by `wf_target_manual()` and `wf_target_shrink()` use the
same canonical `wf_target` structure already consumed by precheck and raking.

## Error Handling

Use existing condition classes:

- malformed margin tables, lambda values, and unsupported methods use
  `wf_error_input`;
- missing columns and incompatible target structures use `wf_error_schema`;
- impossible collapse-plan application uses `wf_error_feasibility` when caused
  by data and `wf_error_internal` only for invariant-breaking bugs.

Every error should include the relevant group, dimension, category, or method in
the message and, where useful, in the condition data payload.

## Testing Strategy

Add focused test files:

- `test-target-manual-shrink.R` for manual target construction, additivity
  checks, shrinkage behavior, and invalid lambda/category errors.
- `test-collapse-suggest.R` for collapse suggestions, unresolved issues, and
  `wf_apply_collapse()` compatibility with old and new plan inputs.
- `test-calibrate.R` for dispatch equivalence to `wf_rake()` and
  `wf_poststrat()`.

Keep the final verification gate unchanged:

- focused tests for each task;
- full `devtools::test()`;
- `devtools::document()`;
- `R CMD build .`;
- `R CMD check --no-manual` on the built tarball;
- language and private-data audits.

## Documentation

Update roxygen for all new exports and add a concise README section showing:

1. manual target construction from a margins table;
2. precheck-driven collapse suggestion and review;
3. unified `wf_calibrate(method = "raking")` usage.
