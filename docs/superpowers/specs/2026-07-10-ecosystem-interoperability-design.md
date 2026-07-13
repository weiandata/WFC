# WFC Ecosystem Interoperability 0.12.0 Design

## Goal

Connect WFC results to the established R survey-analysis and broom-style
ecosystems without changing any weighting engine, numerical result, stable WFC
object key, or zero-hard-dependency commitment.

Version 0.12 implements Release 0.12 from
`inst/design/wfc_future_design.md`:

1. `wf_weights` to `survey::svydesign`;
2. `wf_replicate_weights` to `survey::svrepdesign` with variance equivalence;
3. conditionally registered `tidy()`, `glance()`, and `augment()` methods;
4. a frozen core-package contract for the separate WFCstudio sibling kickoff.

All copyright remains with WEIAN DATA TECH (Beijing) Co., Ltd. Every commit is
authored and committed as `Kunxiang Ma <makunxiang@weiandata.com>`.

## Scope

### Included

- `as_svydesign()` and `as_svrepdesign()` as exported WFC functions.
- A classed `wf_error_dependency` when the suggested `survey` package is not
  installed.
- Strict, order-independent, one-to-one ID alignment with duplicate, missing,
  extra, and reserved-column checks.
- Survey design metadata forwarding for cluster IDs, strata, finite population
  corrections, nesting, degrees of freedom, and supported `...` arguments.
- Replication-type mapping for bootstrap, unstratified/stratified jackknife,
  and BRR while preserving WFC's stored scale and replicate scales.
- Variance-equivalence tests against `survey::svymean()` for all three WFC
  replicate methods.
- Broom-style methods registered against the `generics` generic names while
  retaining `generics` as a suggested dependency.
- An interoperability vignette and a WFCstudio integration-contract document.

### Excluded

- New weighting methods or any calibration-engine semantic change.
- A hard dependency on survey, srvyr, generics, broom, tibble, or dplyr.
- Direct wrappers around every survey estimator; users receive standard survey
  design objects and use the survey/srvyr APIs normally.
- WFCstudio GUI implementation in this repository. WFCstudio remains a sibling
  package and contains no statistical computation.
- Production pipelines, drift validation, or audit JSON, which remain 0.13.

## Survey Design Bridge

```r
as_svydesign(
  w, data, id = "id",
  ids = ~1, strata = NULL, fpc = NULL,
  nest = FALSE, ...
)
```

`w` must inherit from `wf_weights`; `data` must be a non-empty data frame; and
`id` must name a column in `data`. IDs in `data[[id]]` and `w$data$id` are
normalized to trimmed character values, must be unique, and must form identical
sets. Input row order may differ. Missing or extra IDs raise `wf_error_schema`
rather than silently dropping units.

The bridge copies `data`, adds `.wf_weight` in data-row order, and calls
`survey::svydesign()` with WFC's weights. Existing `.wf_weight`, user-supplied
`weights`, `probs`, or `data` overrides are rejected to prevent ambiguous
designs. `ids`, `strata`, `fpc`, `nest`, and non-reserved `...` are forwarded.
The returned standard survey design receives a `wfc_provenance` attribute; WFC
does not subclass or alter survey's computation.

## Replicate Survey Design Bridge

```r
as_svrepdesign(r, data, id = "id", degf = NULL, ...)
```

`r` must inherit from `wf_replicate_weights`. The same exact ID contract aligns
`r$base` and every row of `r$replicates` to `data`. The bridge adds the aligned
base weight as `.wf_weight` and calls `survey::svrepdesign()` with final
replicate weights and `combined.weights = TRUE`.

Replication types map as follows:

| WFC method | survey type |
| --- | --- |
| `bootstrap` | `bootstrap` |
| `jackknife`, no declared strata | `JK1` |
| `jackknife`, declared strata | `JKn` |
| `brr` | `BRR` |

WFC's stored `scale` and `rscales` remain authoritative. Survey's BRR
constructor derives the same `1 / R` scale and therefore receives `rscales` but
not an explicit `scale`, avoiding survey's incompatible-argument warning.
The bridge fixes `mse = TRUE`, making survey variance center replicate
deviations on the full-sample estimate exactly as `wf_variance()` does.

Reserved replicate controls (`variables`, `data`, `weights`, `repweights`,
`type`, `scale`, `rscales`, `combined.weights`, and `mse`) cannot be overridden
through `...`. `degf` remains an explicit analyst control.

## Broom-Style Methods

All methods return base data frames and retain stable English column names.
Localization does not affect these programmatic interfaces.

### `wf_weights`

- `tidy()` returns the unit-level `x$data` table.
- `glance()` returns one row with units, groups, total weight, overall ESS,
  design effect, and method.
- `augment(x, data, id = "id")` performs the same strict ID match and appends
  `.weight` and `.feature` without mutating `data`.

### `wf_diagnostics`

- `tidy()` returns the group diagnostic table.
- `glance()` reports group count, verdict counts, worst design effect, and
  minimum effective sample size.

### `wf_blend_result`

- `tidy()` returns outcome estimates when present, otherwise fused cell
  weights.
- `glance()` reports cell/group counts, lambda range/mean, and quality-warning
  counts.

### `wf_variance_result`

- `tidy()` returns the quantity-level estimate/variance/interval table.
- `glance()` reports method, replicate count, confidence level/type, quantity
  count, and maximum standard error.

Methods use ordinary `S3method(generic, class)` namespace registration and
`Suggests: generics`; WFC never imports or attaches generics. Calling
`generics::tidy()`, `generics::glance()`, or `generics::augment()` dispatches
when generics is installed, while WFC itself remains loadable without it.

## WFCstudio Sibling Contract

The 0.12 core freezes the integration boundary in an English design document:

- WFCstudio accepts sample/population uploads and maps them to ordinary WFC
  constructor arguments.
- It calls `wf_autoweigh()` and renders `wf_autoweigh_result`,
  `wf_quality_report`, ledger rows, artifacts, and classed conditions.
- It performs no weighting, diagnostics, or method selection itself.
- It remains a separate package with its own optional UI/file dependencies.
- The initial implementation is an external release gate; no GUI code is added
  to WFC 0.12.

## Conditions and Stability

- Wrong WFC classes or malformed controls: `wf_error_input`.
- Missing/duplicate/mismatched IDs and reserved output columns:
  `wf_error_schema`.
- Missing suggested packages: `wf_error_dependency`.
- Internal malformed WFC objects or impossible stored replication metadata:
  `wf_error_internal`.

Bridge and tidier functions never mutate WFC objects or input data. Output row
ordering follows `data`; numerical weights and replicate matrices are only
reordered, never recomputed.

## Testing Strategy

- Dependency helper and classed errors.
- Survey bridge order independence, exact weights, design formulas, downstream
  weighted means, metadata, immutability, and ID failures.
- Replicate bridge type/scale/rscale mapping and exact standard-error agreement
  with `wf_variance()` for bootstrap, jackknife, and BRR.
- Tidy/glance schemas and values for all four supported result classes.
- Augment order independence, immutability, and ID/collision failures.
- Namespace registration and package loading with suggested packages absent
  from the attached search path.
- Existing full suite, survey oracle, coverage at least 80%, all vignettes,
  source-package audit, and `R CMD check --as-cran --no-manual`.

## Release Tasks

- Add bridge and tidier modules, tests, documentation, and optional dependency
  declarations.
- Add interoperability and WFCstudio contract documentation.
- Bump to 0.12.0 and update README, Chinese README, NEWS, and CRAN notes.
- Build and verify `WFC_0.12.0.tar.gz` before reporting remote CI, PR, tag, and
  WFCstudio repository work as external gates.
