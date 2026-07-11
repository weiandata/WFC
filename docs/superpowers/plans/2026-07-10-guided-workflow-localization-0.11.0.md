# WFC Guided Workflow and Localization 0.11.0 Implementation Plan

> Execute task by task with the established Superpowers-compatible cycle:
> spec -> failing tests -> focused green tests -> intentional WEIAN DATA commit.

**Goal:** Add bilingual rendering and an auditable `wf_autoweigh()` guided path
over the existing WFC engines.

**Architecture:** `R/i18n.R` loads matched DCF catalogs; existing report/plot
modules consume translation keys; `R/autoweigh.R` orchestrates only public
constructors, prechecks, remediations, engines, diagnostics, and reports.

**Reference:**
`docs/superpowers/specs/2026-07-10-guided-workflow-localization-design.md`,
`inst/design/wfc_future_design.md` Release 0.11, and
`inst/reference/wfc_future_usability.R` as a non-production prototype.

**Branch:** `codex/v0.11.0-guided-workflow`, based on the committed and
company-owned 0.10 branch.

---

### Task 1: Catalog loader and language resolution

**Files:**
- Create: `inst/i18n/en.dcf`
- Create: `inst/i18n/zh_CN.dcf`
- Create: `R/i18n.R`
- Create: `tests/testthat/test-i18n.R`

- [x] Write failing tests for catalog parity, aliases, resolution precedence,
  locale fallback, interpolation, and invalid explicit language.
- [x] Implement lazy base-R DCF loading and stable translation helpers.
- [x] Run focused i18n tests to green.
- [x] Commit as WEIAN DATA: `feat: add bilingual output catalogs`.

### Task 2: Localize reports and plots

**Files:**
- Modify: `R/report.R`, `R/plots.R`
- Modify: `tests/testthat/test-report.R`, `tests/testthat/test-plots.R`
- Regenerate: affected `man/` files

- [x] Write failing English/Chinese rendering tests while asserting stable
  object and table schemas.
- [x] Localize report title/actions/labels and plot titles/axes/legends.
- [x] Run report/plot/i18n filters to green.
- [x] Commit as WEIAN DATA: `feat: localize reports and plot labels`.

### Task 3: Guided workflow and decision ledger

**Files:**
- Create: `R/autoweigh.R`
- Create: `tests/testthat/test-autoweigh.R`

- [x] Write failing tests for raw/ready targets, method routing, collapse loop,
  trim paths, unresolved failures, localization, ledger schema, and immutability.
- [x] Implement target construction, stable ledger helpers, confirmation helper,
  discipline loop, engine routing, diagnosis, report, and print method.
- [x] Run focused tests, then existing calibration/collapse/report filters.
- [x] Commit as WEIAN DATA: `feat: add auditable guided weighting workflow`.

### Task 4: Documentation and 0.11 release metadata

**Files:**
- Create: `vignettes/guided-workflow.Rmd`
- Modify: `README.md`, `README.zh-CN.md`, `NEWS.md`, `DESCRIPTION`
- Modify: `cran-comments.md`
- Regenerate: `NAMESPACE`, `man/`

- [x] Add English code/docs and Chinese text only to the Chinese catalog and
  `README.zh-CN.md`.
- [x] Document language resolution, guided decisions, and review boundaries.
- [x] Bump to 0.11.0 and render every vignette.
- [x] Commit as WEIAN DATA: `docs: prepare WFC 0.11.0 release`.

### Task 5: Release gates

- [x] Confirm local Git author/committer is WEIAN DATA.
- [x] Run all focused filters and the full test suite with the survey oracle.
- [x] Enforce line coverage >= 80%.
- [x] Run `git diff --check` and inspect source-package contents for forbidden
  private/build/agent files.
- [x] Build `WFC_0.11.0.tar.gz` with all vignettes.
- [x] Run `R CMD check --as-cran --no-manual` on the tarball.
- [x] Report remote CI, tag, PR, and real production-cycle checks as external
  release gates rather than code-completion blockers.
