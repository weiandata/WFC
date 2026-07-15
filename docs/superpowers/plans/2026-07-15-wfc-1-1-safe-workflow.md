# WFC 1.1 Safe Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The user prohibited subagents and CodeGraph, so execution must remain inline and use ordinary repository reads.

**Goal:** Add a backward-compatible WFC 1.1 workflow that uses design-only data and verified external targets, requires plan review and approval, serves practitioners and AI agents, and deprecates unsafe 1.0 entry points.

**Architecture:** Add focused S3 objects for design data, verified targets, plans, approvals, locked weights, and post-lock impact. Reuse WFC's existing engines only behind these contracts, extend the current condition/i18n/report/audit systems, and retain 1.0 behavior with per-call deprecation warnings until 2.0.

**Tech Stack:** R (>= 3.6.0), base R, `stats`, `utils`, `digest` for SHA-256, optional `openxlsx` for Excel, roxygen2, testthat edition 3, optional `survey` validation.

## Global Constraints

- Authority: `docs/superpowers/specs/2026-07-15-safe-package-consolidation-design.md`.
- Controlled mode; software verification and statistical validation are separate gates.
- No CodeGraph or subagents.
- TDD for each behavior: focused red, minimal green, regression, then full check.
- English R code, roxygen, tests, config, and commits; Chinese user text only in approved localized files.
- Never edit `NAMESPACE` or `man/*.Rd` manually; regenerate them with roxygen2.
- Use only synthetic, public, or explicitly authorized fixtures.
- Preserve GPL (>= 2), company copyright, and commit identity `Kunxiang Ma <makunxiang@weiandata.com>`.
- WFC 1.1 must preserve 1.0 numerical behavior; unsafe calls warn on every use.
- No force, bypass, ignore-source, auto-approve, auto-relax, auto-widen, or silent-method-switch argument.
- Planning/execution never receive outcomes; impact assessment never recomputes weights.

---

## File structure

| File | Responsibility |
|---|---|
| `R/safety-conditions.R` | Stable safety condition payloads |
| `R/safety-identity.R` | SHA-256 file/object identities |
| `R/design-data.R` | Strict `wf_design_data` |
| `R/target-import.R` | Source metadata, templates, imports, `wf_verified_target` |
| `R/support-merge.R` | Deterministic outcome-blind cell merge planning |
| `R/weight-plan.R` | Outcome-blind plans |
| `R/weight-execution.R` | Approval, execution, locking, attachment |
| `R/impact.R` | Post-lock descriptive impact |
| `R/report.R`, `R/pipeline.R` | Dual views and audit v2 |
| `R/target.R`, `R/calibrate*.R`, `R/pipeline.R` | 1.1 deprecations |
| `inst/extdata/` | Synthetic CSV/Excel/source examples |
| `tests/validation/` and `docs/validation/` | Controlled validation evidence |

### Task 1: Safety conditions and SHA-256 identities

**Files:** Create `R/safety-conditions.R`, `R/safety-identity.R`, and `tests/testthat/test-safety-foundations.R`; modify `DESCRIPTION`.

**Interfaces:** Produces `.wf_safety_abort()`, `.wf_safety_warn()`, `.wf_safety_info()`, `.wf_sha256_file()`, and `.wf_sha256_object()` for all later tasks.

- [ ] **Step 1: Write the failing tests**

```r
test_that("safety errors expose stable machine payloads", {
  err <- tryCatch(.wf_safety_abort(
    "target_period_missing", "Reference period is required.",
    field = "reference_period", next_actions = "supply_source_metadata"
  ), error = identity)
  expect_s3_class(err, "wf_error_safety")
  expect_identical(err$data$code, "target_period_missing")
  expect_identical(err$data$severity, "blocking")
  expect_identical(err$data$next_actions, "supply_source_metadata")
})

test_that("identities are stable SHA-256 strings", {
  p <- tempfile(); writeLines("x", p)
  expect_match(.wf_sha256_file(p), "^[0-9a-f]{64}$")
  expect_identical(.wf_sha256_object(list(a = 1)), .wf_sha256_object(list(a = 1)))
})
```

- [ ] **Step 2: Verify red**

Run: `Rscript -e 'devtools::test(filter = "safety-foundations")'`

Expected: FAIL because the five helpers do not exist.

- [ ] **Step 3: Add `digest` to Imports and implement**

```r
.wf_safety_payload <- function(code, severity, field, evidence, next_actions) {
  list(code = code, severity = severity, field = field,
       evidence = evidence, next_actions = as.character(next_actions))
}
.wf_safety_abort <- function(code, message, field = NULL,
                             evidence = list(), next_actions = character()) {
  wf_abort(message, "wf_error_safety",
           .wf_safety_payload(code, "blocking", field, evidence, next_actions))
}
.wf_safety_warn <- function(code, message, field = NULL,
                            evidence = list(), next_actions = character()) {
  wf_warn(message, "wf_warning_safety",
          .wf_safety_payload(code, "review_required", field, evidence, next_actions))
}
.wf_safety_info <- function(code, field = NULL, evidence = list(),
                            next_actions = character()) {
  .wf_safety_payload(code, "informational", field, evidence, next_actions)
}
.wf_sha256_file <- function(path) {
  if (!.wf_is_string(path) || !file.exists(path))
    .wf_safety_abort("source_file_missing", "Source file does not exist.", "path")
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}
.wf_sha256_object <- function(x) {
  digest::digest(.wf_sanitize_for_hash(x), algo = "sha256", serialize = TRUE)
}
```

- [ ] **Step 4: Verify green and commit**

Run: `Rscript -e 'devtools::test(filter = "safety-foundations|conditions")'`

Expected: zero failures.

```bash
git add DESCRIPTION R/safety-conditions.R R/safety-identity.R tests/testthat/test-safety-foundations.R
git commit -m "feat(safety): add classed safety conditions and identities"
```

### Task 2: Strict design-only data

**Files:** Create `R/design-data.R` and `tests/testthat/test-safety-design-data.R`.

**Interfaces:** Produces `wf_prepare_design(data, id, calibration, base_weight = NULL, strata = NULL, clusters = NULL, fpc = NULL)` and class `wf_design_data` with `data`, `roles`, `identity`, `created`, `package_version`.

- [ ] **Step 1: Write and run the failing tests**

```r
test_that("every design column has an explicit role", {
  d <- data.frame(id = c("a", "b"), sex = c("F", "M"), base = c(1, 2))
  x <- wf_prepare_design(d, "id", "sex", base_weight = "base")
  expect_s3_class(x, "wf_design_data")
  expect_identical(x$roles$calibration, "sex")
  expect_match(x$identity, "^[0-9a-f]{64}$")
})
test_that("unassigned outcome-like columns block", {
  d <- data.frame(id = 1:2, sex = c("F", "M"), outcome = c(1, 0))
  expect_error(wf_prepare_design(d, "id", "sex"), class = "wf_error_safety")
})
```

Run: `Rscript -e 'devtools::test(filter = "safety-design-data")'`

Expected: FAIL because `wf_prepare_design()` does not exist.

- [ ] **Step 2: Implement the constructor**

```r
wf_prepare_design <- function(data, id, calibration, base_weight = NULL,
                              strata = NULL, clusters = NULL, fpc = NULL) {
  roles <- list(id = id, calibration = calibration, base_weight = base_weight,
                strata = strata, clusters = clusters, fpc = fpc)
  assigned <- unique(unlist(roles, use.names = FALSE))
  .require_cols(data, assigned, "design data")
  extra <- setdiff(names(data), assigned)
  if (length(extra)) .wf_safety_abort(
    "design_columns_unassigned",
    sprintf("Design data contain unassigned column(s): %s.", paste(extra, collapse = ", ")),
    evidence = list(columns = extra), next_actions = "remove_or_assign_columns"
  )
  if (anyNA(data[[id]]) || anyDuplicated(data[[id]]))
    .wf_safety_abort("design_id_invalid", "Design IDs must be unique and non-missing.", id)
  if (!is.null(base_weight) &&
      (any(!is.finite(data[[base_weight]])) || any(data[[base_weight]] <= 0)))
    .wf_safety_abort("base_weight_invalid", "Base weights must be finite and positive.", base_weight)
  structure(list(data = data, roles = roles,
                 identity = .wf_sha256_object(list(data = data, roles = roles)),
                 created = .wf_iso_time(), package_version = .wf_package_version()),
            class = "wf_design_data")
}
```

Add roxygen export and a compact print method.

- [ ] **Step 3: Document, verify, and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "safety-design-data")'`

Expected: zero failures and generated export/method entries.

```bash
git add R/design-data.R tests/testthat/test-safety-design-data.R NAMESPACE man
git commit -m "feat(safety): add strict design-only data objects"
```

### Task 3: Verified target import and examples

**Files:** Create `R/target-import.R`, `tests/testthat/test-safety-target-import.R`, `inst/extdata/safe-target-example.csv`, `inst/extdata/safe-target-example.xlsx`, and one `.source.dcf` companion per data file; modify `DESCRIPTION` and `.gitignore`.

**Interfaces:** Produces `wf_target_template(file, dims, by = NULL, example = FALSE)`, `wf_import_target(data_file, source_file, dims, key_map, count, by = NULL, by_key = NULL, production = TRUE)`, and `wf_import_reference(data_file, source_file, dims, feature, by = NULL, production = TRUE)`. Both import functions return `c("wf_verified_target", "wf_target")` with `evidence`, `identity`, `demo_only`, and `source_type`.

- [ ] **Step 1: Write import refusal tests**

```r
test_that("complete source evidence creates a verified target", {
  f <- make_safe_target_files(demo_only = FALSE)
  x <- wf_import_target(f$data, f$source, f$dims, c(sex = "sex"), "count")
  expect_s3_class(x, "wf_verified_target")
  expect_false(x$demo_only)
})
test_that("bad checksum and production demo targets block", {
  f <- make_safe_target_files(demo_only = TRUE)
  expect_error(wf_import_target(f$data, f$source, f$dims,
                                c(sex = "sex"), "count"),
               class = "wf_error_safety")
})
```

Run: `Rscript -e 'devtools::test(filter = "safety-target-import")'`

Expected: FAIL because import/template helpers do not exist.

- [ ] **Step 2: Implement the required DCF schema and readers**

```r
.wf_source_fields <- c(
  "publisher", "dataset_title", "citation", "reference_period",
  "population_scope", "retrieved_at", "license", "checksum_algorithm",
  "checksum", "transformation", "selected_before_outcomes", "demo_only"
)
.wf_read_target_table <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") return(utils::read.csv(path, stringsAsFactors = FALSE))
  if (ext == "xlsx") {
    if (!requireNamespace("openxlsx", quietly = TRUE))
      wf_abort("Package 'openxlsx' is required for Excel targets.",
               "wf_error_dependency", list(package = "openxlsx"))
    return(openxlsx::read.xlsx(path))
  }
  .wf_safety_abort("target_format_unsupported", "Target file must be CSV or XLSX.")
}
```

`wf_import_target()` must require one DCF row and all fields, require SHA-256,
compare the computed checksum, require `selected_before_outcomes: true`, reject
`demo_only: true` in production, call `wf_target_population()`, attach evidence,
and hash the full verified object.

`wf_import_reference()` uses the same metadata and checksum gate, reads only the
declared dimensions and reciprocal-design-weight `feature`, calls
`wf_target_reference()`, and records `source_type = "reference"`. Add a test that
an unassigned outcome column in the reference file is rejected rather than
silently ignored.

- [ ] **Step 3: Implement templates and committed synthetic files**

`wf_target_template()` writes the declared `by`, dimensions, and `count` columns
plus a source DCF named by appending `.source.dcf` to the full data filename.
This keeps CSV and XLSX checksums separate. `example = TRUE` writes synthetic rows and
`demo_only: true`; blank templates write zero rows and `demo_only: false`. Add
`openxlsx` to Suggests and `!inst/extdata/*.xlsx` after `*.xlsx` in `.gitignore`.
Generate CSV and XLSX from identical synthetic data and test identical margins.

- [ ] **Step 4: Verify and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "safety-target-import|data-policy")'`

Expected: zero failures; missing `openxlsx` raises `wf_error_dependency` without affecting CSV.

```bash
git add .gitignore DESCRIPTION R/target-import.R inst/extdata tests/testthat/test-safety-target-import.R NAMESPACE man
git commit -m "feat(safety): import verified external targets"
```

### Task 4: Deterministic outcome-blind cell merging

**Files:** Create `R/support-merge.R` and `tests/testthat/test-safety-support-merge.R`.

**Interfaces:** Produces `wf_plan_cells(design, target, dims, min_cell = 5, max_weight_ratio = 4, boundary = target$by, ladder = NULL)` and class `wf_cell_merge_plan`. Produces internal `.wf_apply_cell_plan(design, target, plan)` for approved execution only.

- [ ] **Step 1: Write conservation, boundary, and outcome-blind tests**

```r
test_that("support merging is deterministic and conserves design totals", {
  f <- make_sparse_safe_workflow_fixture()
  a <- wf_plan_cells(f$design, f$target, f$dims, min_cell = 5, ladder = f$ladder)
  b <- wf_plan_cells(f$design, f$target, f$dims, min_cell = 5, ladder = f$ladder)
  expect_s3_class(a, "wf_cell_merge_plan")
  expect_identical(a$identity, b$identity)
  expect_equal(sum(a$cells_before$n), sum(a$cells_after$n))
  expect_equal(sum(a$cells_before$base_weight), sum(a$cells_after$base_weight))
  expect_true(all(a$map$boundary_before == a$map$boundary_after))
})
test_that("study outcomes cannot alter a merge plan", {
  f <- make_sparse_safe_workflow_fixture(with_outcomes = TRUE)
  p1 <- wf_plan_cells(f$design, f$target, f$dims, ladder = f$ladder)
  f$analysis$outcome <- rev(f$analysis$outcome)
  p2 <- wf_plan_cells(f$design, f$target, f$dims, ladder = f$ladder)
  expect_identical(p1$identity, p2$identity)
})
```

Run: `Rscript -e 'devtools::test(filter = "safety-support-merge")'`

Expected: FAIL because `wf_plan_cells()` does not exist.

- [ ] **Step 2: Implement support-only candidate construction**

Aggregate `design$data` by boundary and calibration dimensions into sample count
and base-weight total. Generate candidates only from explicit ordered adjacency
or a supplied `wf_collapse_ladder`; never accept outcome columns or a custom
scoring callback. Preserve supported singletons. Absorb zero/thin cells only
inside the same boundary. Score candidates lexicographically by moved sample
count, declared demographic distance, base-weight distortion, and merge count.
Do not implement or retain outcome heterogeneity, outcome targets, or target
relaxation from `mergecalib`.

- [ ] **Step 3: Implement deterministic selection and review output**

Use stable radix ordering for ties. Return original/final cells, original-to-final
map, reasons, affected share, unresolved cells, projected max weight ratio,
input identities, settings, and SHA-256 plan identity. If no allowed partition
meets `min_cell` and `max_weight_ratio`, raise `wf_error_feasibility`; never widen
limits. `.wf_apply_cell_plan()` verifies identities and applies exactly the stored
map to design and target without recalculating it.

- [ ] **Step 4: Verify and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "safety-support-merge|collapse|poststrat-plan")'`

Expected: zero failures, conserved totals, no cross-boundary map, and stable identities.

```bash
git add R/support-merge.R tests/testthat/test-safety-support-merge.R NAMESPACE man
git commit -m "feat(safety): add outcome-blind cell merge planning"
```

### Task 5: Outcome-blind weight plan

**Files:** Create `R/weight-plan.R` and `tests/testthat/test-safety-weight-plan.R`; modify `tests/testthat/helper-fixtures.R`.

**Interfaces:** Produces `wf_plan_weights(design, target, dims, method = c("raking", "logit", "poststrat"), bounds = c(0.3, 3), min_cell = 5, cell_plan = NULL)` and class `wf_weight_plan`.

- [ ] **Step 1: Write deterministic no-weights tests**

```r
test_that("planning is deterministic and computes no weights", {
  f <- make_safe_workflow_fixture()
  a <- wf_plan_weights(f$design, f$target, f$dims)
  b <- wf_plan_weights(f$design, f$target, f$dims)
  expect_s3_class(a, "wf_weight_plan")
  expect_identical(a$identity, b$identity)
  expect_null(a$weights)
})
```

Run: `Rscript -e 'devtools::test(filter = "safety-weight-plan")'`

Expected: FAIL because the planner does not exist.

- [ ] **Step 2: Implement plan-only construction**

Validate `wf_design_data`, `wf_verified_target`, non-demo status, identical dims,
finite bounds satisfying `0 < L < 1 < U`, integer `min_cell`, and method-specific
requirements. Call `wf_precheck()`. When `cell_plan` is supplied, require a
`wf_cell_merge_plan` whose design/target identities match.
Store precheck, the immutable cell plan,
issues, settings, input identities, package version, creation time, and
`.wf_sha256_object()` identity. Never call a calibration engine or catch a
feasibility error.

- [ ] **Step 3: Verify and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "safety-weight-plan|precheck|poststrat-plan")'`

Expected: zero failures.

```bash
git add R/weight-plan.R tests/testthat/helper-fixtures.R tests/testthat/test-safety-weight-plan.R NAMESPACE man
git commit -m "feat(safety): add reviewable outcome-blind weight plans"
```

### Task 6: Approval, guided execution, locking, and attachment

**Files:** Create `R/weight-execution.R` and `tests/testthat/test-safety-weight-execution.R`.

**Interfaces:** Produces `wf_approve_plan(plan, approver, role, note = NULL, actor_type = "human")`, `wf_execute_plan(plan, approval, design, target)`, `wf_guided_plan(data, id, calibration, dims, target_file, source_file, source_type = c("population", "reference"), key_map = NULL, count = NULL, feature = NULL, ...)`, `wf_guided_execute(workflow, approval)`, and `wf_attach_weights(data, weights, id, weight_name = ".weight")`.

- [ ] **Step 1: Write refusal and stale-approval tests**

```r
test_that("only a matching human-attested approval executes", {
  f <- make_safe_workflow_fixture(); p <- wf_plan_weights(f$design, f$target, f$dims)
  expect_error(wf_approve_plan(p, "agent", "assistant", actor_type = "agent"),
               class = "wf_error_safety")
  a <- wf_approve_plan(p, "Reviewer", "statistician")
  w <- wf_execute_plan(p, a, f$design, f$target)
  expect_s3_class(w, "wf_locked_weights")
  expect_identical(w$plan_identity, p$identity)
})
```

Run: `Rscript -e 'devtools::test(filter = "safety-weight-execution")'`

Expected: FAIL because approval/execution do not exist.

- [ ] **Step 2: Implement approval and pre-engine identity checks**

`wf_approve_plan()` rejects non-human `actor_type`, empty approver/role, and
non-plan objects, then hashes plan identity, attestation, time, role, and note.
`wf_execute_plan()` compares plan/approval/design/target identities before any
engine call, applies only the stored `wf_cell_merge_plan`, dispatches exactly the approved
method/settings, and returns `c("wf_locked_weights", "wf_weights")` with all
identities in provenance.

`wf_guided_plan()` is the practitioner composition layer: it calls
`wf_prepare_design()`, `wf_import_target()`, `wf_plan_cells()`, and
`wf_plan_weights()` and returns `wf_safe_workflow` containing all four reviewable
objects. It never approves or executes. `wf_guided_execute()` requires an
external `wf_plan_approval` and delegates to `wf_execute_plan()`. Add a test that
guided and lower-level calls produce identical plan identities and weights.

- [ ] **Step 3: Implement safe attachment**

Require unique identical ID sets, preserve full-data row order, reject an
existing `weight_name`, append only the locked weight, and attach the locked
identity as an attribute. Reuse the exact-ID alignment pattern in
`R/interoperability.R`.

- [ ] **Step 4: Verify and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "safety-weight-execution|calibrate|interoperability")'`

Expected: zero failures; identity failures precede calibration.

```bash
git add R/weight-execution.R tests/testthat/test-safety-weight-execution.R NAMESPACE man
git commit -m "feat(safety): require approval before locking weights"
```

### Task 7: Post-lock impact

**Files:** Create `R/impact.R` and `tests/testthat/test-impact.R`.

**Interfaces:** Produces `wf_assess_impact(weights, data, id, outcomes, level = 0.95)` and class `wf_impact` with `summary`, `weight_identity`, `outcomes`, `level`, `created`.

- [ ] **Step 1: Write immutability tests**

```r
test_that("impact compares estimates without changing locked weights", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  w <- make_locked_safe_weights(f); before <- w
  x <- wf_assess_impact(w, f$analysis, "id", c("score", "approved"))
  expect_s3_class(x, "wf_impact")
  expect_true(all(c("outcome", "level", "unweighted", "weighted", "difference") %in%
                  names(x$summary)))
  expect_identical(w, before)
})
```

Run: `Rscript -e 'devtools::test(filter = "impact")'`

Expected: FAIL because the function does not exist.

- [ ] **Step 2: Implement fixed descriptive summaries**

Align locked weights by ID. Numeric non-binary outcomes produce a mean row;
logical, two-level factor, and 0/1 outcomes produce a positive-level proportion;
multi-level factors produce one row per level. Return unweighted/weighted values,
difference, Kish ESS, and normal-approximation SE. Reject targets, callbacks,
selection rules, list columns, dates, and matrices. Never call plan or engine code.

- [ ] **Step 3: Verify outcome mutation isolation and commit**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "impact|variance")'`

Expected: zero failures and identical locked weights after changed outcomes.

```bash
git add R/impact.R tests/testthat/test-impact.R NAMESPACE man
git commit -m "feat(report): assess outcomes only after weight locking"
```

### Task 8: Dual views and audit v2

**Files:** Modify `R/report.R`, `R/pipeline.R`, `inst/i18n/{en,zh_CN}.dcf`, `tests/testthat/test-{report,pipeline}.R`; create `tests/testthat/test-safety-report-audit.R`.

**Interfaces:** Extends `wf_report()` with aliases `decision` and `statistician` and support for `wf_safe_workflow`, `wf_locked_weights`, and `wf_impact`; extends audit to plans, approvals, locked weights, and impacts using schema `wfc_audit_v2`.

- [ ] **Step 1: Write alias and audit tests**

```r
f <- make_report_weights()
expect_identical(wf_report(f$weights, f$target, audience = "decision")$table,
                 wf_report(f$weights, f$target, audience = "manager")$table)
expect_identical(wf_report(f$weights, f$target, audience = "statistician")$table,
                 wf_report(f$weights, f$target, audience = "analyst")$table)
safe <- make_safe_workflow_fixture()
locked <- make_locked_safe_weights(safe)
expect_identical(.wf_audit_payload(locked)$schema, "wfc_audit_v2")
```

Run: `Rscript -e 'devtools::test(filter = "safety-report-audit|report|pipeline")'`

Expected: FAIL on aliases or v2 schema.

- [ ] **Step 2: Implement aliases and v2 fields**

Normalize `decision -> manager` and `statistician -> analyst`, while storing
requested and normalized audience. Preserve identical tables. Audit v2 preserves
all v1 fields and adds design, target, plan, approval, locked-weight, source, and
impact identities, using null for unavailable legacy fields. Add matched English
and Chinese section/action keys without changing programmatic columns. A
`wf_safe_workflow` report shows readiness, merge scope, unresolved issues, and
required next action; a `wf_impact` report shows locked weighted/unweighted
differences without exposing any planning control.

- [ ] **Step 3: Verify and commit**

Run: `Rscript -e 'devtools::test(filter = "safety-report-audit|report|i18n|pipeline")'`

Expected: zero failures and identical English/Chinese schemas.

```bash
git add R/report.R R/pipeline.R inst/i18n tests/testthat
git commit -m "feat(report): add safe workflow views and audit evidence"
```

### Task 9: WFC 1.1 deprecation bridge

**Files:** Modify `R/conditions.R`, `R/target.R`, `R/calibrate.R`, `R/calibrate-linear.R`, `R/pipeline.R`; create `tests/testthat/test-deprecation-1-1.R`.

**Interfaces:** Preserves 1.0 results and emits `wf_warning_deprecated` on every manual target, shrinkage, inline moment, manual pipeline, and runtime margins call.

- [ ] **Step 1: Write per-call warning tests**

```r
expect_warning(wf_target_manual(margins, dims), class = "wf_warning_deprecated")
expect_warning(wf_target_shrink(local, local, 0.5), class = "wf_warning_deprecated")
expect_warning(wf_calibrate(sample, target, method = "ebal", moments = c(x = 1)),
               class = "wf_warning_deprecated")
expect_warning(wf_pipeline(list(mode = "manual"), stages),
               class = "wf_warning_deprecated")
```

Run: `Rscript -e 'devtools::test(filter = "deprecation-1-1")'`

Expected: FAIL because warnings are absent.

- [ ] **Step 2: Extend and call `.wf_warn_deprecated()`**

Add payload fields `feature`, `replacement`, `removal = "2.0.0"`, and
`risk_code`. Warn at each unsafe entry on every call; do not use session options.
Do not change calculations or return objects.

- [ ] **Step 3: Verify compatibility and commit**

Run: `Rscript -e 'devtools::test(filter = "deprecation-1-1|target-manual-shrink|calibrate-methods|pipeline")'`

Expected: zero failures and unchanged numeric results when warnings are captured.

```bash
git add R/conditions.R R/target.R R/calibrate.R R/calibrate-linear.R R/pipeline.R tests/testthat/test-deprecation-1-1.R
git commit -m "feat(deprecation): mark subjective targets for WFC 2.0"
```

### Task 10: Practitioner and AI documentation

**Files:** Create `vignettes/safe-weighting-workflow.Rmd` and `tests/testthat/test-safe-documentation.R`; modify both READMEs, `examples/README.md`, `_pkgdown.yml`, and `inst/stability/api-freeze.md`.

**Interfaces:** Documents the exact safe workflow, CSV/Excel examples, two audiences, and agent refusal contract.

- [ ] **Step 1: Add a failing documentation scan**

Require the vignette and both READMEs to contain prepare/import/plan/approve/
execute/attach/report steps. Require the new safe sections not to contain
`wf_target_manual(` or `moments =`.

Run: `Rscript -e 'devtools::test(filter = "safe-documentation")'`

Expected: FAIL because safe sections are absent.

- [ ] **Step 2: Write complete runnable documentation**

Show synthetic CSV and Excel import, DCF metadata, design-only preparation,
precheck, plan, separate approval, execution, attachment, decision/statistician
reports, audit export, and post-lock impact. Document stable agent condition
payloads, non-interactive operation, no self-approval, and no bypass flags.

- [ ] **Step 3: Build, verify, and commit**

Run: `Rscript -e 'devtools::document(); devtools::build_vignettes(); devtools::test(filter = "safe-documentation|example-data")'`

Expected: vignette build exit 0 and zero test failures.

```bash
git add README.md README.zh-CN.md examples/README.md _pkgdown.yml inst/stability/api-freeze.md vignettes tests/testthat/test-safe-documentation.R NAMESPACE man
git commit -m "docs(safety): document verified outcome-blind weighting"
```

### Task 11: Controlled validation and WFC 1.1 release evidence

**Files:** Create `tests/validation/validate-safe-workflow.R` and `docs/validation/wfc-1.1-safe-workflow-validation.md`; modify `DESCRIPTION`, `NEWS.md`, `CHANGELOG.md`, `cran-comments.md`.

**Interfaces:** Produces deterministic simulation/reference evidence and changes package version to `1.1.0`.

- [ ] **Step 1: Write the validation runner**

Set `set.seed(20260715)`. Cover undercoverage, sparse/empty cells, inconsistent
totals, and extreme base weights. Assert deterministic plans/weights, positive
bounded weights, conserved totals, and outcome-mutation invariance. When
`survey` is installed, compare supported raking margins at documented tolerance;
CI must install `survey` so the reference comparison is not skipped there.

- [ ] **Step 2: Run validation and fill the report from observed output**

Run: `Rscript tests/validation/validate-safe-workflow.R`

Expected: exit 0 and zero failed assertions. Record source revision, dirty state,
session/dependencies, commands, scenarios, comparison, sensitivity, limitations,
and human review status. Do not pre-write a pass claim.

- [ ] **Step 3: Update release metadata and run full verification**

Set `Version: 1.1.0`, add safe workflow and deprecation notes, then run:

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
R CMD build .
R CMD check WFC_1.1.0.tar.gz --as-cran
```

Expected: documentation/test/build exit 0 and check 0 errors/0 warnings. Copy
every NOTE into `cran-comments.md` and review it rather than assuming it harmless.

- [ ] **Step 4: Commit evidence and apply review gate**

```bash
git add DESCRIPTION NEWS.md CHANGELOG.md cran-comments.md tests/validation docs/validation
git commit -m "release: prepare WFC 1.1.0 safe workflow evidence"
```

Inspect every diff; review `digest`/`openxlsx` necessity, maintenance, security,
and licenses; obtain accountable approval and the qualified statistical review
required before public or client reliance.
