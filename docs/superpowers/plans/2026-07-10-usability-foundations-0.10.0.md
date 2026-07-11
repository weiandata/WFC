# WFC Usability Foundations 0.10.0 Implementation Plan

> **Execution mode:** Follow the Superpowers `spec -> plan -> TDD -> focused
> verification -> commit` loop task by task. The standalone Superpowers skill is
> not installed in this environment, so this plan is executed directly with the
> same red/green discipline.

**Goal:** Ship `wf_auto_trim()`, `wf_suggest_ladder()`, `wf_report()`, and the
0.10 plot methods without changing numerical weighting semantics or adding hard
dependencies.

**Architecture:** Four focused modules (`R/auto-trim.R`,
`R/suggest-ladder.R`, `R/report.R`, `R/plots.R`) build on the existing public
objects. One additive change in `R/propensity.R` provides a specific S3 subclass
and raw propensity values for plotting. Rendering and graphics stay base R.

**Reference:**
`docs/superpowers/specs/2026-07-10-usability-foundations-design.md`,
`inst/design/wfc_future_design.md` Release 0.10, and
`inst/reference/wfc_future_usability.R` as a prototype rather than production
code.

**Branch:** `codex/v0.10.0-usability`, based on the committed 0.9.1
stabilization branch.

---

### Task 1: Trim recommendation engine

**Files:**
- Create: `R/auto-trim.R`
- Create: `tests/testthat/test-auto-trim.R`

- [ ] Write failing validation, frontier, recommendation, print, and failure-
  capture tests.
- [ ] Run `testthat::test_local(filter = "auto-trim")` and confirm missing API
  failures.
- [ ] Implement candidate execution, warning/error capture, recommendation,
  provenance, and print method.
- [ ] Run focused tests to green.
- [ ] Commit `feat: add automatic trim recommendation frontier`.

### Task 2: Collapse-ladder drafting

**Files:**
- Create: `R/suggest-ladder.R`
- Create: `tests/testthat/test-suggest-ladder.R`

- [ ] Write failing tests for adjacent merging, worst-group support, affected-
  share ordering, no-op drafts, validation, immutability, and print output.
- [ ] Run the focused filter and confirm missing API failures.
- [ ] Implement the deterministic partition algorithm and validated ladder
  artifact.
- [ ] Run focused tests to green.
- [ ] Commit `feat: add reviewable collapse ladder drafts`.

### Task 3: Structured quality report

**Files:**
- Create: `R/report.R`
- Create: `tests/testthat/test-report.R`

- [ ] Write failing tests for manager/analyst tables, traffic lights, weight and
  blend sources, propensity sections, language validation, Markdown/HTML
  escaping, file output, print, and `as.data.frame()`.
- [ ] Run the focused filter and confirm missing API failures.
- [ ] Implement report construction separately from Markdown/HTML rendering.
- [ ] Run focused tests to green.
- [ ] Commit `feat: add structured weighting quality reports`.

### Task 4: Base plot methods and propensity subclass

**Files:**
- Create: `R/plots.R`
- Modify: `R/propensity.R`
- Create: `tests/testthat/test-plots.R`
- Modify: `tests/testthat/test-propensity.R`

- [ ] Write failing temporary-device tests for all five plot methods and the
  propensity subclass/raw-overlap contract.
- [ ] Run focused plot/propensity tests and confirm failures.
- [ ] Add the subclass/data fields and implement graphics methods with parameter
  restoration.
- [ ] Run focused tests to green, then run existing propensity/blend tests.
- [ ] Commit `feat: add usability plot methods`.

### Task 5: Documentation and release metadata

**Files:**
- Modify: roxygen blocks in the four new R modules
- Regenerate: `NAMESPACE`, `man/`
- Create: `vignettes/usability-foundations.Rmd`
- Modify: `README.md`, `README.zh-CN.md`, `NEWS.md`, `DESCRIPTION`
- Modify: `cran-comments.md`

- [ ] Add runnable examples and the 0.10 vignette using only `wfc_example` and
  simulated in-memory data.
- [ ] Export the three new functions and register all S3 methods.
- [ ] Bump to 0.10.0 and document additive class fields/objects.
- [ ] Render the vignette and run examples.
- [ ] Commit `docs: prepare WFC 0.10.0 release`.

### Task 6: Release gates

- [ ] Run all focused test filters.
- [ ] Run `testthat::test_local(reporter = "summary")` with `survey` installed.
- [ ] Enforce line coverage >= 80% with `covr`.
- [ ] Run `git diff --check` and confirm private/build artifacts are absent.
- [ ] Build the source tarball with vignettes.
- [ ] Run `R CMD check --as-cran --no-manual` on the tarball.
- [ ] Review the final diff and report any external gates (remote CI and real
  production-cycle validation) separately from code completion.
