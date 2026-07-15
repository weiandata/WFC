# WFC 2.0 Safety Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The user prohibited subagents and CodeGraph.

**Goal:** Make the validated WFC 1.1 safe workflow the only supported WFC 2.0 weighting contract and remove subjective-target interfaces.

**Architecture:** Preserve WFC 1.1 safe objects and engines, enforce them at public calibration and pipeline boundaries, remove deprecated constructors/arguments, migrate all current documentation, then validate and release through a 2.0 candidate.

**Tech Stack:** R (>= 3.6.0), WFC 1.1 safe objects, base R, `digest`, optional `openxlsx`, roxygen2, testthat edition 3, optional `survey` reference validation.

## Global Constraints

- Begin only after WFC 1.1 is released, validated, and has carried the warnings for one full minor release.
- Authority: `docs/superpowers/specs/2026-07-15-safe-package-consolidation-design.md`.
- Controlled mode; no CodeGraph or subagents; TDD for each removal and boundary.
- Preserve safe WFC 1.1 object fields and condition codes.
- No legacy shim, unsafe override, or warning-only fallback in WFC 2.0.
- English code/generated docs; approved Simplified Chinese only in localized paths.
- Regenerate `NAMESPACE`/`man/` through roxygen; use synthetic fixtures; preserve company identity and GPL (>= 2).

---

### Task 1: Freeze the WFC 2.0 contract

**Files:** Create `inst/stability/api-2.0.md` and `docs/migration/wfc-1-to-2.md`; modify `DESCRIPTION` and `tests/testthat/test-stability-contracts.R`.

**Interfaces:** Defines retained safe exports, removed exports/arguments, stable objects/conditions, and changes development version to `2.0.0.9000`. This task leaves the code green; removal assertions are added in Task 2.

- [ ] **Step 1: Write failing export assertions**

```r
contract <- readLines(root_file("inst/stability/api-2.0.md"), warn = FALSE)
expect_true(any(grepl("Retained safe exports", contract, fixed = TRUE)))
expect_true(any(grepl("Removed interfaces", contract, fixed = TRUE)))
expect_true(any(grepl("No supported replacement", contract, fixed = TRUE)))
```

Run: `Rscript -e 'devtools::test(filter = "stability-contracts")'`

Expected: FAIL because `inst/stability/api-2.0.md` does not exist.

- [ ] **Step 2: Write the exact contract and migration table**

List retained signatures, removed signatures/arguments, stable object fields,
condition taxonomy, and executable migrations. State “no replacement” for
pass-rate, outcome-interval, subjective manual target, target shrinkage, and
inline outcome-moment behavior. Set `Version: 2.0.0.9000`.

Run: `Rscript -e 'devtools::test(filter = "stability-contracts")'`

Expected: zero failures after the contract document is present.

- [ ] **Step 3: Commit the contract before code removal**

```bash
git add DESCRIPTION inst/stability/api-2.0.md docs/migration/wfc-1-to-2.md tests/testthat/test-stability-contracts.R
git commit -m "docs(api): define the WFC 2.0 safety contract"
```

### Task 2: Remove manual targets, shrinkage, and inline moments

**Files:** Modify `R/target.R`, `R/calibrate.R`, `R/calibrate-linear.R`, `tests/testthat/test-target-manual-shrink.R`, and `tests/testthat/test-calibrate-methods.R`; create `tests/testthat/test-safety-removals-2-0.R`.

**Interfaces:** Removes exports `wf_target_manual()` and `wf_target_shrink()`; retains categorical entropy calibration only with verified margins; rejects `moments`.

- [ ] **Step 1: Write and run removal tests**

```r
test_that("subjective target APIs are absent", {
  expect_false("wf_target_manual" %in% getNamespaceExports("WFC"))
  expect_false("wf_target_shrink" %in% getNamespaceExports("WFC"))
})
test_that("inline moments are blocked", {
  f <- make_weightflow_fixture()
  f$sample$x <- seq_len(nrow(f$sample))
  expect_error(wf_calibrate(f$sample, f$target, method = "ebal", moments = c(x = 1)),
               class = "wf_error_safety")
})
```

Run: `Rscript -e 'devtools::test(filter = "safety-removals-2-0")'`

Expected: FAIL while deprecated APIs remain.

- [ ] **Step 2: Remove constructors and enforce the refusal**

Delete the roxygen blocks and implementations for both constructors. Remove
their behavior tests but retain migration/export assertions. In `wf_calibrate()`,
detect `"moments" %in% names(list(...))` and call:

```r
.wf_safety_abort(
  "inline_moments_unsupported",
  "WFC 2.0 does not accept inline target moments. Use verified external margins.",
  "moments", next_actions = "import_verified_external_margins"
)
```

Remove unreachable moment-building/report code. Keep categorical entropy tests.

- [ ] **Step 3: Regenerate, verify, and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "safety-removals-2-0|calibrate-methods|stability-contracts")'`

Expected: zero failures and no removed API in `NAMESPACE`/`man/`.

```bash
git add R tests/testthat NAMESPACE man
git commit -m "feat(api): remove subjective target interfaces"
```

### Task 3: Enforce safe objects at all weighting boundaries

**Files:** Modify `R/calibrate.R`, `R/rake.R`, `R/poststrat.R`, `R/autoweigh.R`, `R/pipeline.R`, and `R/weight-execution.R`; create `tests/testthat/test-safety-boundaries-2-0.R`; modify pipeline/autoweigh tests.

**Interfaces:** Requires `wf_design_data` and `wf_verified_target`; removes pipeline `manual` mode and `wf_run(..., margins)`.

- [ ] **Step 1: Write and run boundary refusal tests**

```r
test_that("raw samples and arbitrary targets do not reach engines", {
  f <- make_safe_workflow_fixture()
  expect_error(wf_calibrate(f$design$data, f$target, method = "raking"),
               class = "wf_error_safety")
  expect_error(wf_plan_weights(f$design, unclass(f$target), f$dims),
               class = "wf_error_safety")
})
test_that("manual pipelines are blocked", {
  expect_error(wf_pipeline(list(mode = "manual"),
                           list(calibrate = list(method = "raking"))),
               class = "wf_error_safety")
})
```

Run: `Rscript -e 'devtools::test(filter = "safety-boundaries-2-0")'`

Expected: FAIL while raw 1.x paths remain.

- [ ] **Step 2: Add one verified internal dispatcher**

Create `.wf_execute_verified_engine(design, target, method, settings)` in
`R/weight-execution.R`. It validates classes and identities before calling
non-exported engine functions with `design$data`. Route `wf_execute_plan()`
through it. Public calibration/guided functions accept the safe contract or
raise `wf_error_safety`; no arbitrary ready `wf_target` reaches an engine.

- [ ] **Step 3: Remove manual pipeline paths**

Set target modes to `c("population", "reference", "object")`; require object
mode to inherit `wf_verified_target`; delete the manual target builder branch;
remove `margins` from `wf_run()` and the installed contract. Supplying margins
must fail as unused, not be ignored.

- [ ] **Step 4: Verify and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "safety-boundaries-2-0|safety-weight-execution|pipeline|autoweigh")'`

Expected: zero failures and only verified objects reach engines.

```bash
git add R tests/testthat NAMESPACE man inst/stability/api-2.0.md docs/migration/wfc-1-to-2.md
git commit -m "feat(safety): enforce verified weighting inputs"
```

### Task 4: Remove unsafe current documentation

**Files:** Modify both READMEs, `vignettes/methods-soft-ebal.Rmd`, `vignettes/production-infrastructure.Rmd`, `vignettes/safe-weighting-workflow.Rmd`, `_pkgdown.yml`, `NEWS.md`, `CHANGELOG.md`, and `tests/testthat/test-safe-documentation.R`.

**Interfaces:** Makes verified weighting the only current documented path while preserving historical NEWS entries.

- [ ] **Step 1: Extend the documentation scan and verify red**

Scan current READMEs/vignettes/examples and fail on `wf_target_manual()`,
`wf_target_shrink()`, inline `moments`, `mode = "manual"`, or runtime margins.
Exclude historical specs, plans, and NEWS from the scan.

Run: `Rscript -e 'devtools::test(filter = "safe-documentation")'`

Expected: FAIL with exact current files using removed APIs.

- [ ] **Step 2: Rewrite examples and migration guidance**

Every replacement shows source evidence, import, design-only data, plan,
approval, execution, and audit. The migration guide gives no workaround for
prohibited behavior.

- [ ] **Step 3: Build, verify, and commit**

Run: `Rscript -e 'devtools::document(); devtools::build_vignettes(); devtools::test(filter = "safe-documentation")'`

Expected: vignette build exit 0 and zero failures.

```bash
git add README.md README.zh-CN.md vignettes _pkgdown.yml NEWS.md CHANGELOG.md docs/migration tests/testthat/test-safe-documentation.R NAMESPACE man
git commit -m "docs(migration): make verified weighting the WFC 2.0 path"
```

### Task 5: Adversarial validation and release candidate

**Files:** Create `tests/validation/validate-wfc-2-safety.R` and `docs/validation/wfc-2.0-safety-validation.md`; modify `DESCRIPTION`, `cran-comments.md`, `NEWS.md`.

**Interfaces:** Produces Controlled evidence for `2.0.0-rc.1` and final `2.0.0`.

- [ ] **Step 1: Implement adversarial attempts**

Attempt manual margins, pass-rate tables, outcome means, outcome intervals,
unverified/demo targets, stale approvals, changed design, agent approval, and raw
engine calls. Assert each stops with its documented `wf_error_safety` code before
engine execution.

- [ ] **Step 2: Run all validation**

```bash
Rscript tests/validation/validate-safe-workflow.R
Rscript tests/validation/validate-wfc-2-safety.R
Rscript -e 'devtools::test()'
```

Expected: validation exit 0 and zero test failures.

- [ ] **Step 3: Write the report from observed evidence**

Record refusal codes, simulation/reference/sensitivity results, source revision,
dirty state, platforms/dependencies, limitations, accountable approval, and
qualified human statistical review scope. Passing tests do not imply approval.

- [ ] **Step 4: Build/check the candidate and commit evidence**

Use valid numeric R package version `2.0.0`; identify the pre-release as
`v2.0.0-rc.1` in Git/release metadata. Run:

```bash
Rscript -e 'devtools::document()'
R CMD build .
R CMD check WFC_2.0.0.tar.gz --as-cran
```

Expected: 0 errors/0 warnings; record and review every NOTE.

```bash
git add DESCRIPTION NEWS.md cran-comments.md tests/validation docs/validation
git commit -m "release: prepare WFC 2.0.0 release candidate"
```

Do not create public/client reliance until accountable and qualified human
statistical approvals are recorded.
