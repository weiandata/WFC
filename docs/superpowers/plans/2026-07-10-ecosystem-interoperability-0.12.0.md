# WFC Ecosystem Interoperability 0.12.0 Implementation Plan

> Execute task by task with the established Superpowers-compatible cycle:
> spec -> failing tests -> focused green tests -> intentional WEIAN DATA commit.

**Goal:** Connect WFC weights, replicate weights, diagnostics, blend results,
and variance results to survey and broom-style consumers.

**Architecture:** `R/interoperability.R` owns dependency and ID contracts plus
survey bridges; `R/tidiers.R` owns base-data-frame S3 projections; existing
engines and object schemas remain unchanged.

**Reference:**
`docs/superpowers/specs/2026-07-10-ecosystem-interoperability-design.md`,
`inst/design/wfc_future_design.md` Release 0.12, and the non-production
prototype in `inst/reference/wfc_future_infrastructure.R`.

**Branch:** `codex/v0.12.0-interoperability`, based on the verified 0.11.0
release candidate.

---

### Task 1: Survey design bridge

**Files:**
- Create: `R/interoperability.R`
- Create: `tests/testthat/test-interoperability-survey.R`
- Regenerate: `NAMESPACE`, `man/`

- [x] Write failing tests for dependency errors, exact/order-independent ID
  joins, downstream survey estimates, design metadata, collisions, and input
  immutability.
- [x] Implement shared dependency/ID helpers and `as_svydesign()`.
- [x] Run survey bridge and existing oracle tests to green.
- [x] Commit as WEIAN DATA: `feat: add survey design bridge`.

### Task 2: Replicate survey design bridge

**Files:**
- Modify: `R/interoperability.R`
- Create: `tests/testthat/test-interoperability-replicates.R`
- Regenerate: `man/`

- [x] Write failing tests for bootstrap, JK1/JKn, and BRR type mapping,
  scale/rscale preservation, and `svymean()` variance equivalence.
- [x] Implement `as_svrepdesign()` with exact ID alignment and fixed MSE
  semantics.
- [x] Run replicate, variance, and survey interoperability tests to green.
- [x] Commit as WEIAN DATA: `feat: bridge replicate weights to survey`.

### Task 3: Broom-style tidiers

**Files:**
- Create: `R/tidiers.R`
- Create: `tests/testthat/test-tidiers.R`
- Modify: `DESCRIPTION`
- Regenerate: `NAMESPACE`, `man/`

- [x] Write failing tests for tidy/glance projections, augment alignment,
  namespace dispatch, collisions, and immutability.
- [x] Implement methods for weights, diagnostics, blend, and variance results.
- [x] Add `generics` to Suggests without a hard import.
- [x] Run tidier and affected object-family tests to green.
- [x] Commit as WEIAN DATA: `feat: add broom-style result tidiers`.

### Task 4: Documentation and 0.12 release metadata

**Files:**
- Create: `vignettes/ecosystem-interoperability.Rmd`
- Create: `inst/design/wfcstudio_contract.md`
- Modify: `README.md`, `README.zh-CN.md`, `NEWS.md`, `DESCRIPTION`
- Modify: `cran-comments.md`

- [x] Document survey/srvyr use, tidier schemas, ID contracts, suggested
  dependencies, and variance equivalence.
- [x] Freeze the no-statistics WFCstudio sibling-package contract.
- [x] Bump to 0.12.0 and render every vignette.
- [x] Commit as WEIAN DATA: `docs: prepare WFC 0.12.0 release`.

### Task 5: Release gates

- [x] Confirm every 0.12 commit uses the WEIAN DATA identity.
- [x] Run all focused filters and the full test suite with survey/generics.
- [x] Enforce line coverage >= 80%.
- [x] Run `git diff --check` and audit the source package for forbidden files.
- [x] Build `WFC_0.12.0.tar.gz` with all vignettes.
- [x] Run `R CMD check --as-cran --no-manual` on the tarball.
- [x] Report remote CI, PR, tag, real downstream survey/srvyr adoption, and the
  WFCstudio sibling repository as external release gates.
