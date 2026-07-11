# Initial R Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the repository root into a verifiable `weightflow` R package built from the approved design and the existing core reference implementation.

**Architecture:** The package keeps a base-R core and S3 objects. The original design and reference prototype are preserved under English `inst/` paths, while package code is split into focused files under `R/`. Private source data moves to ignored local storage, and package examples use a generated simulated dataset.

**Tech Stack:** R 4.6.0, base R, stats, utils, testthat 3, roxygen2, devtools, git.

---

Repository root: `<repo>`

## File Structure

- Create `<repo>/DESCRIPTION`: R package metadata.
- Create `<repo>/LICENSE`: MIT license metadata for R.
- Create `<repo>/.Rbuildignore`: package-build exclusions.
- Modify `<repo>/.gitignore`: keep current private data exclusions and add package build outputs.
- Create `<repo>/R/*.R`: implementation files split by responsibility.
- Create `<repo>/tests/testthat/*.R`: package behavior tests.
- Create `<repo>/tests/testthat.R`: testthat entrypoint.
- Move `<repo>/legacy-design-input/weightflow_design.md` to `<repo>/inst/design/weightflow_design.md`.
- Move `<repo>/legacy-core-input/weightflow_core.R` to `<repo>/inst/reference/weightflow_core.R`.
- Move private source data from `<repo>/legacy-private-data/` to `<repo>/private-data/source/`.
- Create `<repo>/data-raw/make-weightflow-example.R`: reproducible simulated data generator.
- Create `<repo>/data/weightflow_example.rda`: generated simulated package data.
- Create `<repo>/README.md`: English project overview and example.
- Create `<repo>/README.zh-CN.md`: only Chinese-language repository file.
- Create `<repo>/AGENTS.md`: future-agent handoff.

### Task 1: Bootstrap Package Metadata And Safe Paths

**Files:**
- Create: `<repo>/DESCRIPTION`
- Create: `<repo>/LICENSE`
- Create: `<repo>/.Rbuildignore`
- Modify: `<repo>/.gitignore`
- Move: `<repo>/legacy-design-input/weightflow_design.md`
- Move: `<repo>/legacy-core-input/weightflow_core.R`
- Move: `<repo>/legacy-private-data/2022-simulated-source.xlsx`
- Move: `<repo>/legacy-private-data/weight_data_V4.0.RData`

- [ ] **Step 1: Create package directories**

Run:

```bash
mkdir -p R tests/testthat inst/design inst/reference data-raw data private-data/source
```

Expected: exit code 0.

- [ ] **Step 2: Move reference design and prototype into English paths**

Run:

```bash
mv legacy-design-input/weightflow_design.md inst/design/weightflow_design.md
mv legacy-core-input/weightflow_core.R inst/reference/weightflow_core.R
mv legacy-private-data/2022-simulated-source.xlsx private-data/source/2022-simulated-source.xlsx
mv legacy-private-data/weight_data_V4.0.RData private-data/source/weight-data-v4-source.RData
```

Expected: exit code 0 and all source materials remain recoverable under English paths.

- [ ] **Step 3: Create `DESCRIPTION`**

Write exactly:

```text
Package: weightflow
Title: Workflow-Oriented Survey Weight Calibration
Version: 0.1.0
Authors@R: c(
    person("Weightflow", "Contributors", email = "weightflow-maintainers@example.com", role = c("aut", "cre"))
  )
Description: Provides a disciplined precheck, execution, and diagnostics workflow
    for survey weighting and raking with schema-agnostic dimensions and canonical
    target objects.
License: MIT + file LICENSE
Encoding: UTF-8
Roxygen: list(markdown = TRUE)
RoxygenNote: 7.3.2
LazyData: true
Suggests:
    testthat (>= 3.0.0)
Config/testthat/edition: 3
```

- [ ] **Step 4: Create `LICENSE`**

Write exactly:

```text
YEAR: 2026
COPYRIGHT HOLDER: Weightflow contributors
```

- [ ] **Step 5: Create `.Rbuildignore`**

Write exactly:

```text
^\.git$
^\.gitignore$
^\.codegraph$
^docs$
^data-raw$
^private-data$
^.*\.Rproj$
^\.Rproj\.user$
^\.DS_Store$
^README\.zh-CN\.md$
^AGENTS\.md$
```

- [ ] **Step 6: Extend `.gitignore`**

Ensure it contains these lines in addition to the current rules:

```text
*.tar.gz
*.Rcheck/
```

- [ ] **Step 7: Verify private files are ignored**

Run:

```bash
git status --short --ignored
```

Expected: `private-data/` appears as ignored, not staged. `inst/design/weightflow_design.md` and `inst/reference/weightflow_core.R` appear as untracked.

- [ ] **Step 8: Commit package bootstrap**

Run:

```bash
git add DESCRIPTION LICENSE .Rbuildignore .gitignore inst/design/weightflow_design.md inst/reference/weightflow_core.R
git commit -m "chore: bootstrap package metadata"
```

Expected: commit succeeds and no private data is included.

### Task 2: Write Failing Tests For Core Package Behavior

**Files:**
- Create: `<repo>/tests/testthat.R`
- Create: `<repo>/tests/testthat/helper-fixtures.R`
- Create: `<repo>/tests/testthat/test-dims-target.R`
- Create: `<repo>/tests/testthat/test-precheck.R`
- Create: `<repo>/tests/testthat/test-rake-diagnostics.R`
- Create: `<repo>/tests/testthat/test-data-policy.R`

- [ ] **Step 1: Create `tests/testthat.R`**

Write exactly:

```r
library(testthat)
library(weightflow)

test_check("weightflow")
```

- [ ] **Step 2: Create the shared fixture**

Write exactly to `tests/testthat/helper-fixtures.R`:

```r
make_weightflow_fixture <- function() {
  sample <- data.frame(
    id = sprintf("r%02d", 1:16),
    province = rep(c("A", "B"), each = 8),
    gender = rep(c("female", "male", "female", "male"), times = 4),
    age = rep(c("young", "young", "old", "old"), times = 4),
    stringsAsFactors = FALSE
  )

  pop <- data.frame(
    province = rep(c("A", "B"), each = 4),
    gender = rep(c("female", "male", "female", "male"), times = 2),
    age = rep(c("young", "young", "old", "old"), times = 2),
    count = c(40, 60, 60, 40, 30, 70, 50, 50),
    stringsAsFactors = FALSE
  )

  dims <- wf_dims(
    gender = c("female", "male"),
    age = c("young", "old")
  )

  target <- wf_target_population(
    pop = pop,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = dims,
    by = "province"
  )

  list(sample = sample, pop = pop, dims = dims, target = target)
}
```

- [ ] **Step 3: Create dims and target tests**

Write exactly to `tests/testthat/test-dims-target.R`:

```r
test_that("wf_dims validates named dimensions and collapse ladders", {
  expect_s3_class(wf_dims(gender = c("female", "male")), "wf_dims")
  expect_error(wf_dims(c("female", "male")), class = "wf_error_input")
  expect_error(
    wf_dims(gender = NULL, .collapse = list(age = list(step1 = c("1" = "all")))),
    class = "wf_error_input"
  )
})

test_that("population target validates schema and counts", {
  fixture <- make_weightflow_fixture()

  expect_s3_class(fixture$target, "wf_target")
  expect_equal(fixture$target$dims, c("gender", "age"))
  expect_equal(fixture$target$groups$A$total, 200)
  expect_equal(unname(fixture$target$groups$A$margins$gender["female"]), 100)

  expect_error(
    wf_target_population(
      pop = fixture$pop,
      key_map = c(gender = "missing", age = "age"),
      count = "count",
      dims = fixture$dims,
      by = "province"
    ),
    class = "wf_error_schema"
  )

  bad_pop <- fixture$pop
  bad_pop$count[1] <- -1
  expect_error(
    wf_target_population(
      pop = bad_pop,
      key_map = c(gender = "gender", age = "age"),
      count = "count",
      dims = fixture$dims,
      by = "province"
    ),
    class = "wf_error_input"
  )
})

test_that("target invariant rejects non-additive margins", {
  fixture <- make_weightflow_fixture()
  target <- fixture$target
  target$groups$A$margins$gender["female"] <- target$groups$A$margins$gender["female"] + 1

  expect_error(
    weightflow:::.wf_validate_target(target),
    class = "wf_error_input"
  )
})

test_that("reference target screens invalid feature values", {
  fixture <- make_weightflow_fixture()
  ref <- fixture$sample
  ref$feature <- rep(0.5, nrow(ref))

  target <- wf_target_reference(ref, feature = "feature", dims = fixture$dims, by = "province")
  expect_s3_class(target, "wf_target")

  ref$feature[1] <- 0
  expect_error(
    wf_target_reference(ref, feature = "feature", dims = fixture$dims, by = "province"),
    class = "wf_error_input"
  )
})
```

- [ ] **Step 4: Create precheck tests**

Write exactly to `tests/testthat/test-precheck.R`:

```r
test_that("precheck reports unknown sample categories", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$gender[1] <- "other"

  pc <- wf_precheck(sample, fixture$target, id = "id")

  expect_false(pc$ok)
  expect_true("cat_unknown_in_sample" %in% pc$issues$check)
})

test_that("precheck reports infeasible positive target cells", {
  fixture <- make_weightflow_fixture()
  sample <- subset(fixture$sample, !(province == "B" & gender == "male"))

  pc <- wf_precheck(sample, fixture$target, id = "id", na = "drop")

  expect_false(pc$ok)
  expect_true("cat_infeasible" %in% pc$issues$check)
})

test_that("precheck reports duplicate ids", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$id[2] <- sample$id[1]

  pc <- wf_precheck(sample, fixture$target, id = "id")

  expect_false(pc$ok)
  expect_true("dup_id" %in% pc$issues$check)
})

test_that("precheck reports overloaded missing dimensions", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$gender[1] <- NA
  sample$age[1] <- NA

  pc <- wf_precheck(sample, fixture$target, id = "id", max_na_dims = 1)

  expect_false(pc$ok)
  expect_true("na_overload" %in% pc$issues$check)
})
```

- [ ] **Step 5: Create raking and diagnostics tests**

Write exactly to `tests/testthat/test-rake-diagnostics.R`:

```r
test_that("wf_rake refuses blocked prechecks", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$gender[1] <- "other"

  expect_error(
    wf_rake(sample, fixture$target, id = "id"),
    class = "wf_error_feasibility"
  )
})

test_that("wf_rake returns positive weights matching target margins", {
  fixture <- make_weightflow_fixture()

  weights <- wf_rake(fixture$sample, fixture$target, id = "id", tol = 1e-8)

  expect_s3_class(weights, "wf_weights")
  expect_true(all(weights$data$weight > 0))
  expect_equal(sum(weights$data$weight[weights$data$group == "A"]), 200, tolerance = 1e-6)
  expect_equal(sum(weights$data$weight[weights$data$group == "B"]), 200, tolerance = 1e-6)

  for (group in names(fixture$target$groups)) {
    for (dim_name in fixture$target$dims) {
      expect_equal(
        weights$achieved[[group]][[dim_name]],
        fixture$target$groups[[group]]$margins[[dim_name]],
        tolerance = 1e-6
      )
    }
  }
})

test_that("wf_diagnose reports diagnostics and margin error", {
  fixture <- make_weightflow_fixture()
  weights <- wf_rake(fixture$sample, fixture$target, id = "id", tol = 1e-8)

  diag <- wf_diagnose(weights, target = fixture$target)

  expect_s3_class(diag, "wf_diagnostics")
  expect_true(all(c("ess", "deff", "verdict", "margin_maxerr") %in% names(diag$table)))
  expect_true(all(diag$table$margin_maxerr <= 1e-4))
})
```

- [ ] **Step 6: Create publication policy tests**

Write exactly to `tests/testthat/test-data-policy.R`:

```r
root_file <- function(path) {
  candidates <- c(path, file.path("..", "..", path))
  existing <- candidates[file.exists(candidates)]
  normalizePath(existing[[1]], mustWork = TRUE)
}

test_that("git ignore protects private source data formats", {
  gitignore <- readLines(root_file(".gitignore"), warn = FALSE)

  expect_true("*.xlsx" %in% gitignore)
  expect_true("*.RData" %in% gitignore)
  expect_true("private-data/" %in% gitignore)
})

test_that("R build ignore excludes development-only local files", {
  rbuildignore <- readLines(root_file(".Rbuildignore"), warn = FALSE)

  expect_true("^private-data$" %in% rbuildignore)
  expect_true("^data-raw$" %in% rbuildignore)
  expect_true("^\\.codegraph$" %in% rbuildignore)
})
```

- [ ] **Step 7: Run tests and verify they fail because implementation is absent**

Run:

```bash
Rscript -e 'devtools::test()'
```

Expected: FAIL with missing exported functions such as `wf_dims()` or package load failure because `R/` has not been implemented.

### Task 3: Implement Conditions, Utilities, Dimensions, And Targets

**Files:**
- Create: `<repo>/R/conditions.R`
- Create: `<repo>/R/utils.R`
- Create: `<repo>/R/dims.R`
- Create: `<repo>/R/target.R`
- Source reference: `<repo>/inst/reference/weightflow_core.R`
- Test: `<repo>/tests/testthat/test-dims-target.R`

- [ ] **Step 1: Implement condition helpers**

Create `R/conditions.R` from `inst/reference/weightflow_core.R` lines 11-23. Add roxygen internal tags above both functions:

```r
#' Abort with a classed weightflow condition.
#'
#' @param message Error message.
#' @param class Primary condition class.
#' @param data Machine-readable condition payload.
#' @keywords internal
wf_abort <- function(message, class, data = list()) {
  stop(structure(
    class = c(class, "wf_error", "error", "condition"),
    list(message = message, call = sys.call(-1), data = data)
  ))
}

#' Warn with a classed weightflow condition.
#'
#' @param message Warning message.
#' @param class Primary condition class.
#' @param data Machine-readable condition payload.
#' @keywords internal
wf_warn <- function(message, class, data = list()) {
  warning(structure(
    class = c(class, "wf_warning", "warning", "condition"),
    list(message = message, call = sys.call(-1), data = data)
  ))
}
```

- [ ] **Step 2: Implement shared utilities**

Create `R/utils.R` using exact function bodies from `inst/reference/weightflow_core.R`:

```text
lines 25-33: .chr(), .require_cols()
lines 61-126: .wf_new_target(), .wf_validate_target(), .wf_group_keys(), .wf_scale_groups()
lines 388-393: .grp_sum()
```

Keep these functions unexported. Add only concise `#' @keywords internal` roxygen comments.

- [ ] **Step 3: Implement `wf_dims()`**

Create `R/dims.R` using exact function body from `inst/reference/weightflow_core.R` lines 39-55. The roxygen block must include:

```r
#' Declare calibration dimensions
#'
#' @param ... Named dimension-level pairs. Use `NULL` to infer levels from the target.
#' @param .collapse Named list of collapse ladders.
#'
#' @return A `wf_dims` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(gender = c("female", "male"), age = c("young", "old"))
#' dims
```

- [ ] **Step 4: Implement target constructors**

Create `R/target.R` using exact function bodies from `inst/reference/weightflow_core.R`:

```text
lines 128-174: wf_target_population()
lines 176-222: wf_target_reference()
```

Add `@export` roxygen blocks for both functions. Examples must use small inline data frames and must not read private files.

- [ ] **Step 5: Run target tests**

Run:

```bash
Rscript -e 'devtools::test(filter = "dims-target")'
```

Expected: all tests in `test-dims-target.R` pass.

- [ ] **Step 6: Commit target layer**

Run:

```bash
git add R/conditions.R R/utils.R R/dims.R R/target.R tests/testthat.R tests/testthat/helper-fixtures.R tests/testthat/test-dims-target.R tests/testthat/test-precheck.R tests/testthat/test-rake-diagnostics.R tests/testthat/test-data-policy.R
git commit -m "feat: add dimensions and target constructors"
```

Expected: commit records the tests and the implementation that makes the target tests green.

### Task 4: Implement Precheck

**Files:**
- Create: `<repo>/R/precheck.R`
- Source reference: `<repo>/inst/reference/weightflow_core.R`
- Test: `<repo>/tests/testthat/test-precheck.R`

- [ ] **Step 1: Run precheck tests and verify red state**

Run:

```bash
Rscript -e 'devtools::test(filter = "precheck")'
```

Expected: FAIL because `wf_precheck()` is not implemented.

- [ ] **Step 2: Implement precheck functions**

Create `R/precheck.R` using exact function bodies from `inst/reference/weightflow_core.R`:

```text
lines 228-231: .wf_issue()
lines 233-339: wf_precheck()
lines 341-358: print.wf_precheck()
```

Add an `@export` roxygen block for `wf_precheck()` and an `@export` roxygen line for `print.wf_precheck()`.

- [ ] **Step 3: Run precheck tests and verify green state**

Run:

```bash
Rscript -e 'devtools::test(filter = "precheck")'
```

Expected: all tests in `test-precheck.R` pass.

- [ ] **Step 4: Commit precheck layer**

Run:

```bash
git add R/precheck.R tests/testthat/test-precheck.R
git commit -m "feat: add structured precheck"
```

Expected: commit succeeds.

### Task 5: Implement Collapse, Raking, And Diagnostics

**Files:**
- Create: `<repo>/R/collapse.R`
- Create: `<repo>/R/rake.R`
- Create: `<repo>/R/diagnostics.R`
- Modify: `<repo>/R/utils.R`
- Source reference: `<repo>/inst/reference/weightflow_core.R`
- Test: `<repo>/tests/testthat/test-rake-diagnostics.R`

- [ ] **Step 1: Run raking and diagnostics tests and verify red state**

Run:

```bash
Rscript -e 'devtools::test(filter = "rake-diagnostics")'
```

Expected: FAIL because `wf_rake()` and `wf_diagnose()` are not implemented.

- [ ] **Step 2: Implement collapse**

Create `R/collapse.R` using exact function body from `inst/reference/weightflow_core.R` lines 364-382. Add an `@export` roxygen block for `wf_apply_collapse()`.

- [ ] **Step 3: Implement raking engine**

Create `R/rake.R` using exact function bodies from `inst/reference/weightflow_core.R`:

```text
lines 395-412: .wf_ipf()
lines 414-450: .wf_expand_group()
lines 452-556: wf_rake()
lines 558-565: print.wf_weights()
```

Add an `@export` roxygen block for `wf_rake()` and an `@export` roxygen line for `print.wf_weights()`.

- [ ] **Step 4: Implement diagnostics**

Create `R/diagnostics.R` using exact function bodies from `inst/reference/weightflow_core.R`:

```text
lines 571-606: wf_diagnose()
lines 608-612: print.wf_diagnostics()
```

Add an `@export` roxygen block for `wf_diagnose()` and an `@export` roxygen line for `print.wf_diagnostics()`.

- [ ] **Step 5: Run raking and diagnostics tests and verify green state**

Run:

```bash
Rscript -e 'devtools::test(filter = "rake-diagnostics")'
```

Expected: all tests in `test-rake-diagnostics.R` pass.

- [ ] **Step 6: Run the full test suite**

Run:

```bash
Rscript -e 'devtools::test()'
```

Expected: all tests pass.

- [ ] **Step 7: Commit raking layer**

Run:

```bash
git add R/collapse.R R/rake.R R/diagnostics.R R/utils.R tests/testthat/test-rake-diagnostics.R
git commit -m "feat: add raking and diagnostics"
```

Expected: commit succeeds.

### Task 6: Generate Simulated Package Data

**Files:**
- Create: `<repo>/data-raw/make-weightflow-example.R`
- Create: `<repo>/data/weightflow_example.rda`
- Create: `<repo>/R/data.R`
- Create: `<repo>/tests/testthat/test-example-data.R`

- [ ] **Step 1: Write failing data test**

Write exactly to `tests/testthat/test-example-data.R`:

```r
test_that("weightflow_example contains only simulated package data", {
  data("weightflow_example", package = "weightflow", envir = environment())

  expect_true(exists("weightflow_example"))
  expect_true(is.list(weightflow_example))
  expect_true(all(c("sample", "population", "dims") %in% names(weightflow_example)))
  expect_true(is.data.frame(weightflow_example$sample))
  expect_true(is.data.frame(weightflow_example$population))
  expect_s3_class(weightflow_example$dims, "wf_dims")
  expect_false(any(grepl("source", names(weightflow_example))))
})
```

Run:

```bash
Rscript -e 'devtools::test(filter = "example-data")'
```

Expected: FAIL because `weightflow_example` does not exist.

- [ ] **Step 2: Create simulated data generator**

Write exactly to `data-raw/make-weightflow-example.R`:

```r
set.seed(20260709)

sample <- data.frame(
  id = sprintf("sim-%03d", 1:80),
  province = rep(c("North", "South"), each = 40),
  gender = rep(c("female", "male"), times = 40),
  age = rep(c("young", "old", "young", "old"), times = 20),
  stringsAsFactors = FALSE
)

population <- data.frame(
  province = rep(c("North", "South"), each = 4),
  gender = rep(c("female", "male", "female", "male"), times = 2),
  age = rep(c("young", "young", "old", "old"), times = 2),
  count = c(120, 100, 80, 100, 90, 110, 100, 100),
  stringsAsFactors = FALSE
)

dims <- wf_dims(
  gender = c("female", "male"),
  age = c("young", "old")
)

weightflow_example <- list(
  sample = sample,
  population = population,
  dims = dims
)

save(weightflow_example, file = "data/weightflow_example.rda", compress = "xz")
```

- [ ] **Step 3: Create data documentation**

Write exactly to `R/data.R`:

```r
#' Simulated survey weighting example data
#'
#' A small, fully simulated dataset for examples and tests. It contains no
#' private source records.
#'
#' @format A list with three elements:
#' \describe{
#'   \item{sample}{Simulated respondent-level sample data.}
#'   \item{population}{Simulated population cell counts.}
#'   \item{dims}{A `wf_dims` object for `gender` and `age`.}
#' }
#' @source Generated by `data-raw/make-weightflow-example.R`.
"weightflow_example"
```

- [ ] **Step 4: Generate package data**

Run:

```bash
Rscript -e 'devtools::load_all(); source("data-raw/make-weightflow-example.R")'
```

Expected: creates `data/weightflow_example.rda`.

- [ ] **Step 5: Run data test and verify green state**

Run:

```bash
Rscript -e 'devtools::test(filter = "example-data")'
```

Expected: all tests in `test-example-data.R` pass.

- [ ] **Step 6: Commit simulated data**

Run:

```bash
git add data-raw/make-weightflow-example.R data/weightflow_example.rda R/data.R tests/testthat/test-example-data.R
git commit -m "data: add simulated example dataset"
```

Expected: commit succeeds and private source files remain ignored.

### Task 7: Add Documentation And Handoff Files

**Files:**
- Create: `<repo>/README.md`
- Create: `<repo>/README.zh-CN.md`
- Create: `<repo>/AGENTS.md`
- Test: `<repo>/tests/testthat/test-data-policy.R`

- [ ] **Step 1: Run policy tests and verify `.Rbuildignore` coverage**

Run:

```bash
Rscript -e 'devtools::test(filter = "data-policy")'
```

Expected: all tests in `test-data-policy.R` pass after Task 1.

- [ ] **Step 2: Create `README.md`**

Write an English README with these exact sections:

````markdown
# weightflow

`weightflow` is a workflow-oriented R package for survey weighting and raking.
It emphasizes a disciplined precheck -> execute -> diagnose loop for
multi-source survey calibration.

## Status

This repository is in the first package build stage. The 0.1.0 scope is the
base-R raking workflow described in `inst/design/weightflow_design.md`.

## Data Policy

Private source spreadsheets and RData files are not committed and are not
included in package builds. Examples use the simulated `weightflow_example`
dataset.

## Minimal Example

```r
library(weightflow)

data(weightflow_example)

dims <- weightflow_example$dims
target <- wf_target_population(
  pop = weightflow_example$population,
  key_map = c(gender = "gender", age = "age"),
  count = "count",
  dims = dims,
  by = "province"
)

precheck <- wf_precheck(weightflow_example$sample, target, id = "id")
precheck

weights <- wf_rake(weightflow_example$sample, target, id = "id")
wf_diagnose(weights, target = target)
```
````

- [ ] **Step 3: Create `README.zh-CN.md`**

Create the concise root-level Chinese overview file. Keep its content only in
`README.zh-CN.md`; do not duplicate the Chinese prose elsewhere in the
repository.

- [ ] **Step 4: Create `AGENTS.md`**

Write exactly:

```markdown
# AGENTS.md

## Project Authority

Follow `inst/design/weightflow_design.md` as the design authority and
`inst/reference/weightflow_core.R` as the 0.1.0 implementation reference.

## Language Policy

Use English for package code, tests, documentation, configuration, and commit
messages. The only Chinese-language repository file is `README.zh-CN.md`.

## Data Policy

Files under `private-data/` are local private source data. Do not commit them,
read them into examples, or include them in package builds. Package examples use
only simulated data generated from `data-raw/make-weightflow-example.R`.

## Development Policy

Use test-driven development for behavior changes. Run focused tests after each
change, then run the full package verification before claiming completion.

## Git Policy

Stage files intentionally. Do not add private source data, local build outputs,
`.codegraph/`, `.DS_Store`, or generated check directories.
```

- [ ] **Step 5: Commit documentation**

Run:

```bash
git add README.md README.zh-CN.md AGENTS.md tests/testthat/test-data-policy.R
git commit -m "docs: add project handoff and overview"
```

Expected: commit succeeds.

### Task 8: Generate R Documentation And Run Package Verification

**Files:**
- Generate: `<repo>/NAMESPACE`
- Generate: `<repo>/man/*.Rd`
- Modify: `<repo>/DESCRIPTION` if roxygen updates `RoxygenNote`

- [ ] **Step 1: Generate roxygen documentation**

Run:

```bash
Rscript -e 'devtools::document()'
```

Expected: exit code 0, generated `NAMESPACE`, and generated `man/` files.

- [ ] **Step 2: Run full test suite**

Run:

```bash
Rscript -e 'devtools::test()'
```

Expected: all tests pass.

- [ ] **Step 3: Run package check**

Run:

```bash
R CMD check --no-manual .
```

Expected: check completes with no errors. If warnings or notes remain, read the check log and fix package issues that are in scope for 0.1.0.

- [ ] **Step 4: Refresh CodeGraph after source files exist**

Run:

```bash
codegraph init -i
```

Expected: command exits 0. If the file count remains zero, report CodeGraph's R-language indexing limitation and continue with the R verification evidence.

- [ ] **Step 5: Inspect git state**

Run:

```bash
git status --short --ignored
```

Expected: source and docs changes are visible; private data remains ignored.

- [ ] **Step 6: Commit generated docs and verification-ready package**

Run:

```bash
git add DESCRIPTION NAMESPACE man R tests data data-raw README.md README.zh-CN.md AGENTS.md .Rbuildignore .gitignore
git commit -m "chore: document and verify package"
```

Expected: commit succeeds with no private data staged.

### Task 9: Final Verification Report

**Files:**
- Read: `<repo>/*check/00check.log` if `R CMD check` creates a check directory.

- [ ] **Step 1: Re-run final commands freshly**

Run:

```bash
Rscript -e 'devtools::test()'
Rscript -e 'devtools::document()'
R CMD check --no-manual .
git status --short
```

Expected: tests and documentation succeed, package check has no errors, and git status contains no accidentally staged private data.

- [ ] **Step 2: Report exact outcomes**

Final response must include:

```text
Tests: command and pass/fail status
Documentation: command and pass/fail status
R CMD check: command and error/warning/note summary
Git: branch, latest commit, and remaining untracked or ignored private files
```

- [ ] **Step 3: Mention git author identity if still automatic**

Run:

```bash
git log -1 --format='%an <%ae>'
```

Expected: report the configured author value and recommend setting a public GitHub-ready identity before publishing if it still uses a local network email.
