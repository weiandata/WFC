# CRAN comments

## Test environments

* Local: macOS Tahoe 26.5.1, R 4.6.0 (aarch64-apple-darwin23)
* GitHub Actions: R devel, release, and oldrel-1 on Linux; R release on
  macOS and Windows

## Release

This is the initial CRAN submission for WFC 1.0.0. The package was previously
developed under the name `weightflow`, but that package name is already in use
on CRAN by an unrelated package. The 1.0.0 release freezes the public WFC core
API and documents the compatibility policy in `inst/stability/api-freeze.md`.

## R CMD check results

Local `R CMD check --as-cran --no-manual`:

* 0 errors
* 0 warnings
* 0 notes

Remote repository-index and system-clock lookups were disabled for the local
check because the release environment has no outbound network access. All
package, code, documentation, example, test, and vignette checks completed.
There are no downstream dependencies because this is a first submission.

## Additional verification

* The test suite includes an optional numerical oracle against `survey::rake()`.
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
