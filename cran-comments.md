# CRAN comments

## Test environments

* Local: macOS Tahoe 26.5.2, R 4.6.0 (aarch64-apple-darwin23)
* GitHub Actions: R devel, release, and oldrel-1 on Linux; R release on
  macOS and Windows

## Release

This is the initial CRAN submission for WFC, now at version 1.1.0. The package
was previously developed under the name `weightflow`, but that package name is
already in use on CRAN by an unrelated package. Version 1.0.0 froze the public
WFC core API. Version 1.1.0 adds verified external target import, outcome-blind
planning, identity-bound human approval, locked-weight execution, post-lock
impact assessment, and auditable reports. Subjective legacy target controls warn
in 1.1 and are scheduled for removal in 2.0.0.

WFC is distributed under GPL (>= 2); `inst/COPYRIGHTS` records the copyright
boundary for separately distributed optional dependencies.

## R CMD check results

Local `R CMD check WFC_1.1.0.tar.gz --as-cran`:

* 0 errors
* 0 warnings
* 2 notes

The notes were:

1. `New submission`. This is expected because WFC has not previously been
   published on CRAN.
2. `Skipping checking HTML validation: 'tidy' doesn't look like recent enough
   HTML Tidy.` The local checker completed the PDF manual and all package,
   documentation, example, test, and vignette checks. This note concerns the
   local external HTML Tidy executable rather than generated R documentation.

There are no downstream dependencies because this is a first submission.

## Additional verification

* A deterministic controlled validation covers supported undercoverage,
  sparse/empty cells, tampered targets, extreme base weights, outcome isolation,
  bounds, and total conservation. With `survey` 4.5, WFC's weighted margins
  differed from the independent `survey` tables by at most `7.8e-12`.
* CI installs `survey` and makes the numerical reference comparison mandatory.
  Independent package-level statistical review by Jinyan Zhu and accountable
  release approval by Kunxiang Ma were completed separately from the software
  checks and are recorded in the validation report.
* CI enforces at least 80% line coverage.
* Guided-workflow tests cover raw and ready targets, raking, bounded logit,
  post-stratification, declared remediation, trim outcomes, interactive refusal,
  input immutability, localized narration, and stable decision-ledger keys.
* English and Simplified Chinese catalogs are checked for key parity. Plot
  methods are exercised on non-interactive PDF devices, and the report suite
  verifies localized structured, Markdown, escaped standalone HTML, and file
  output.
* Survey interoperability tests verify exact, order-independent ID alignment,
  survey design metadata, and downstream weighted estimates. Replicate bridge
  tests prove `survey::svymean()` standard errors equal `wf_variance()` for
  bootstrap, JK1/JKn, and BRR designs.
* Broom-style methods are tested through the suggested `generics` package and
  return base data frames; WFC has no hard survey, srvyr, generics, broom,
  tibble, or dplyr dependency.
* Package examples and vignettes use only the bundled simulated `wfc_example`
  data. Files under `private-data/` are excluded from builds and are never read
  by examples or tests.
* WFCstudio is a separate sibling package. The WFC core package contains only
  the integration contract and has no GUI, Shiny, xlsx, or other hard UI
  dependency.
