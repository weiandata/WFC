# WFC Usability Foundations 0.10.0 Design

## Goal

Ship the usability foundation committed in `inst/design/wfc_future_design.md`
Release 0.10: a structured weighting-quality report, base-graphics methods,
data-driven trim recommendations, and reviewable collapse-ladder drafts. This
release adds no weighting method and does not implement the 0.11 guided path.

The release must preserve the package's central discipline:

- automation recommends but never silently applies a trim or collapse;
- all computations reuse existing engines and diagnostics;
- result objects remain structured and auditable;
- the core gains no hard dependency;
- existing `wf_weights` and condition contracts remain compatible.

## Scope

### Included

1. `wf_auto_trim()` plus `print()` and `plot()` methods.
2. `wf_suggest_ladder()` plus `print()` and a validated ladder artifact.
3. `wf_report()` for `wf_weights` and `wf_blend_result`, with manager and
   analyst projections, object/Markdown/HTML outputs, `print()`, and
   `as.data.frame()`.
4. Base-graphics methods for `wf_weights`, `wf_diagnostics`,
   `wf_blend_result`, and propensity-weight results.
5. A non-breaking `wf_propensity_weights` subclass and stored propensity values
   needed for overlap-density plotting.
6. Documentation, examples, vignette, release metadata, and tests.

### Excluded

- `wf_autoweigh()` and its decision ledger (0.11).
- Chinese/localized report rendering and message catalogs (0.11).
- survey/broom bridges and WFCstudio (0.12).
- pipeline specifications, drift validation, and audit JSON (0.13).
- new calibration methods or changes to numerical weighting semantics.

## Public APIs

### `wf_auto_trim()`

```r
wf_auto_trim(
  sample, target, id = NULL,
  caps = c(2, 3, 4, 5, 6, 8, 10, 12),
  lo = 0.05,
  max_deff = 6,
  max_residual = 0.02,
  ...
)
```

The function evaluates every finite upper cap plus an untrimmed (`Inf`)
baseline by rerunning `wf_rake()`. For each candidate it records feasibility,
worst group design effect, worst relative margin residual, warning count, and a
classed error summary if the fit fails.

Recommendation rule:

1. If the untrimmed fit meets both criteria, recommend `Inf` (no trimming).
2. Otherwise recommend the loosest finite cap meeting both criteria.
3. If none meet both criteria, recommend `NA_real_`.

The result is `wf_auto_trim` with `$frontier`, `$recommended_cap`, `$criteria`,
and `$provenance`. It never changes the sample or returns final production
weights. `trim` is reserved and rejected in `...` because the function owns the
candidate trim settings.

### `wf_suggest_ladder()`

```r
wf_suggest_ladder(sample, target, dims, min_cell = 5)
```

For each dimension and target group, compute support for every declared level.
If the worst-group support is below `min_cell`, iteratively merge the thinnest
partition into the adjacent partition with lower support. Adjacency follows the
explicit order in `dims$vars`; dimensions with inferred (`NULL`) levels are
rejected because alphabetical adjacency is not a defensible automatic choice.

Dimensions are ordered into cumulative draft levels by ascending affected
sample share, so the least information-losing merge comes first. The result is
`wf_ladder_draft` containing:

- `$levels`: reviewable named mappings;
- `$affected_share` and `$support_before`;
- `$min_cell` and `$provenance`;
- `$ladder`: a validated `wf_collapse_ladder` ready to use only after review.

The function does not mutate `dims`, the sample, or target, and does not apply
the ladder.

### `wf_report()`

```r
wf_report(
  w, target = NULL,
  audience = c("manager", "analyst"),
  lang = NULL,
  output = c("object", "markdown", "html"),
  file = NULL
)
```

Supported sources are `wf_weights` (including composed, post-stratification,
and propensity results) and `wf_blend_result`.

For `wf_weights`, the common table comes from `wf_diagnose()`. Manager output
adds traffic-light status, a publish-separately flag, and a concrete action.
Analyst output retains all diagnostic columns and method-specific sections:

- post-stratification cell/collapse audit when present;
- propensity overlap and balance tables when present;
- composed-stage provenance when present.

For `wf_blend_result`, the common table is the group summary and the structured
sections include lambda, one-source/trimmed-lambda diagnostics, and sensitivity.

`output = "object"` returns `wf_quality_report`. Markdown and HTML return one
character string when `file = NULL`; with `file`, they write the document and
invisibly return the structured report. HTML is generated with base R and
escaped content, with no rmarkdown dependency at runtime.

`lang` accepts only `NULL` or `"en"` in 0.10. Any other value raises
`wf_error_input` explaining that localization ships in 0.11. This freezes the
future signature without prematurely shipping the localization layer.

### Plot methods

- `plot.wf_weights()`: per-group histograms, mean line, and raking trim bounds
  when recorded; `max_groups` limits panels.
- `plot.wf_diagnostics()`: design-effect and ESS-share dot charts.
- `plot.wf_blend_result()`: lambda sensitivity curves; errors clearly when the
  result was created with `sensitivity = FALSE`.
- `plot.wf_propensity_weights()`: overlap densities and a before/after absolute
  standardized-mean-difference love plot.
- `plot.wf_auto_trim()`: two-panel bias-variance frontier (design effect and
  margin residual against cap).

All methods use base graphics, restore graphics parameters on exit, and return
their input invisibly.

## Class and Data Compatibility

`wf_propensity()` changes its class from `"wf_weights"` to
`c("wf_propensity_weights", "wf_weights")`. Existing `inherits(x,
"wf_weights")`, `wf_compose()`, and print dispatch continue to work. Its
`$overlap` gains raw online/reference propensity vectors for visualization;
existing quantiles and counts remain unchanged.

New S3 classes are additive:

- `wf_auto_trim`
- `wf_ladder_draft`
- `wf_quality_report`
- `wf_propensity_weights` (subclass)

## Validation and Conditions

All public inputs use existing classed conditions:

- malformed arguments, unsupported language/output, invalid caps/criteria, or
  unordered dimensions: `wf_error_input`;
- missing sample columns: `wf_error_schema`;
- no usable sample group or impossible ladder construction:
  `wf_error_feasibility`.

Candidate-specific raking failures in `wf_auto_trim()` are captured in the
frontier rather than aborting the whole sweep. Invalid top-level inputs abort
before any fit.

## Testing Strategy

- Recommendation cases: no trim needed, finite cap selected, and none feasible.
- Candidate failure/warning capture and deterministic sorted frontier.
- Ladder adjacency, dimension ordering by affected share, validation, no-op
  draft, and no mutation.
- Manager/analyst report schemas; Markdown/HTML escaping and file output;
  method-specific propensity/blend sections.
- Every plot method through a temporary PDF device, including validation paths
  and graphics-parameter restoration.
- Propensity subclass compatibility with existing APIs.
- Existing full suite remains green; coverage stays above 80%; vignettes build;
  `R CMD check --as-cran --no-manual` has no error or warning.

## Release Tasks

- Add implementation modules, tests, roxygen documentation, and S3
  registrations.
- Add a 0.10 usability vignette and README sections.
- Bump `DESCRIPTION` to 0.10.0 and add `NEWS.md` release notes.
- Regenerate `NAMESPACE` and `man/` with roxygen2.
- Build the source tarball with vignettes and run the full release gates.
