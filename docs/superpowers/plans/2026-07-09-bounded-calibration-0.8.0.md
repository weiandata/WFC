# Bounded Calibration (GREG / logit) 0.8.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Deville–Särndal calibration engine reachable via `wf_calibrate(method = "greg" | "logit")` — `logit` gives weights bounded within `bounds = c(L, U)` by construction (merging rake-then-trim), `greg` is the linear/unbounded estimator — both calibrating to the existing `wf_target` categorical margins.

**Architecture:** One internal engine in `R/calibrate-linear.R`: a distance object supplying `F`/`F'`, a per-group constraint builder (intercept + one-hot with one dropped reference level per dim), and a Newton solver for `λ` in `Σ d_i F(x_i'λ) x_i = t` (linear GREG converges in one step). Grouped per `by` like `wf_rake()`, returns the standard `wf_weights`. `wf_calibrate()` gains `greg`/`logit` routes; `print.wf_weights` gains a branch. No new top-level export; no core engine touched.

**Tech Stack:** Base R (`solve`, matrix ops, `exp`), the existing `wf_abort`/`wf_warn` helpers, `.chr` / `.wf_group_keys` utils, `testthat` edition 3, roxygen2/devtools.

**Reference:** Spec at `docs/superpowers/specs/2026-07-09-bounded-calibration-design.md`. Idioms: `R/conditions.R` (`wf_abort`/`wf_warn`), `R/utils.R` (`.chr`, `.wf_group_keys`), `R/rake.R:110` (`wf_rake` group loop, na handling, provenance), `R/rake.R:253` (`print.wf_weights` branches), `R/calibrate.R` (`wf_calibrate` dispatcher), `R/target.R` (`target$groups[[g]]$margins[[dim]]` named count vectors, `target$dims`, `target$by`). Internal `.wf_*` helpers are callable directly in tests. `make_weightflow_fixture()` (in `tests/testthat/helper-fixtures.R`) has `$sample` (id/province/gender/age) and `$target` (grouped by province, gender+age margins).

**Test command:** `Rscript -e 'devtools::test(filter = "calibrate-linear")'`. Expect `FAIL 0`.

**Branch:** create `feat/bounded-calibration-0.8.0` off `main` before Task 1.

**Note on the dispatcher signature:** `wf_calibrate()` keeps its minimal formal signature `function(sample, target, method = "raking", ...)`; `bounds` / `init_weight` / `na` / `tol` / `max_iter` for greg/logit flow through `...` to the engine (the same way rake/poststrat args already do). The spec's expanded signature is illustrative; routing via `...` avoids argument collisions with rake/poststrat.

---

### Task 1: Distance functions (`.wf_lincal_dist`)

**Files:**
- Create: `R/calibrate-linear.R`
- Test: `tests/testthat/test-calibrate-linear.R`

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-calibrate-linear.R`:

```r
test_that(".wf_lincal_dist linear gives F(u)=1+u and F'(u)=1", {
  dist <- .wf_lincal_dist("linear", NULL)
  u <- c(-0.5, 0, 0.5, 2)
  expect_equal(dist$F(u), 1 + u)
  expect_equal(dist$Fp(u), rep(1, length(u)))
})

test_that(".wf_lincal_dist logit maps to (L,U) with F(0)=1 and unit slope at 0", {
  L <- 0.3; U <- 3
  dist <- .wf_lincal_dist("logit", c(L, U))
  u <- seq(-10, 10, by = 0.5)
  fu <- dist$F(u)
  expect_true(all(fu > L & fu < U))
  expect_equal(dist$F(0), 1)
  expect_equal(dist$Fp(0), 1)          # slope at 0 matches the linear distance
})

test_that(".wf_lincal_dist logit F' matches a numeric derivative", {
  dist <- .wf_lincal_dist("logit", c(0.5, 4))
  u0 <- 0.7
  numeric <- (dist$F(u0 + 1e-6) - dist$F(u0 - 1e-6)) / (2e-6)
  expect_equal(dist$Fp(u0), numeric, tolerance = 1e-5)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: FAIL — `could not find function ".wf_lincal_dist"`.

- [ ] **Step 3: Implement `.wf_lincal_dist` and the version helper**

Create `R/calibrate-linear.R`:

```r
#' Return the loaded package version for provenance.
#'
#' @keywords internal
#' @noRd
.wf_lincal_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("weightflow")),
    error = function(e) "0.8.0"
  )
}

#' Build a calibration distance object (weight-generating function and slope).
#'
#' @param distance "linear" (GREG) or "logit" (bounded).
#' @param bounds Two-element `c(L, U)` for logit; ignored for linear.
#' @keywords internal
#' @noRd
.wf_lincal_dist <- function(distance, bounds) {
  if (distance == "linear") {
    return(list(
      F = function(u) 1 + u,
      Fp = function(u) rep(1, length(u))
    ))
  }
  L <- bounds[1]
  U <- bounds[2]
  A <- (U - L) / ((1 - L) * (U - 1))
  list(
    F = function(u) {
      e <- exp(A * u)
      (L * (U - 1) + U * (1 - L) * e) / ((U - 1) + (1 - L) * e)
    },
    Fp = function(u) {
      e <- exp(A * u)
      (U - L)^2 * e / ((U - 1) + (1 - L) * e)^2
    }
  )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/calibrate-linear.R tests/testthat/test-calibrate-linear.R
git commit -m "feat: add calibration distance functions (linear/logit)"
```

---

### Task 2: Constraint builder (`.wf_lincal_build`)

**Files:**
- Modify: `R/calibrate-linear.R`
- Test: `tests/testthat/test-calibrate-linear.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-calibrate-linear.R`:

```r
test_that(".wf_lincal_build makes an intercept + dropped-reference-level matrix", {
  sub <- data.frame(g = c("a", "a", "b", "b"), stringsAsFactors = FALSE)
  gr <- list(total = 4, margins = list(g = c(a = 3, b = 1)))
  built <- .wf_lincal_build(sub, dvars = "g", gr = gr)

  # intercept column + one column for the retained level "b" (a is the ref)
  expect_equal(ncol(built$X), 2)
  expect_equal(built$X[, 1], rep(1, 4))
  expect_equal(built$X[, 2], c(0, 0, 1, 1))
  expect_equal(built$t, c(4, 1))          # total, then b's margin
})

test_that(".wf_lincal_build stacks multiple dims, dropping one level each", {
  sub <- data.frame(
    g = c("a", "b", "a", "b"),
    h = c("x", "x", "y", "y"),
    stringsAsFactors = FALSE
  )
  gr <- list(total = 4,
             margins = list(g = c(a = 2, b = 2), h = c(x = 2, y = 2)))
  built <- .wf_lincal_build(sub, dvars = c("g", "h"), gr = gr)
  # intercept + (g: drop a, keep b) + (h: drop x, keep y) = 3 columns
  expect_equal(ncol(built$X), 3)
  expect_equal(built$t, c(4, 2, 2))
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: FAIL — `could not find function ".wf_lincal_build"`.

- [ ] **Step 3: Implement `.wf_lincal_build`**

Append to `R/calibrate-linear.R`:

```r
#' Build the calibration constraint matrix and target vector for one group.
#'
#' @param sub Group's (complete-case) sample subset.
#' @param dvars Calibration dimension names.
#' @param gr A target group: `list(total, margins)`.
#' @keywords internal
#' @noRd
.wf_lincal_build <- function(sub, dvars, gr) {
  n <- nrow(sub)
  cols <- list(rep(1, n))
  t <- gr$total
  for (d in dvars) {
    lev <- names(gr$margins[[d]])
    for (l in lev[-1]) {   # drop the first level as the reference
      cols[[length(cols) + 1]] <- as.numeric(.chr(sub[[d]]) == l)
      t <- c(t, gr$margins[[d]][[l]])
    }
  }
  list(X = do.call(cbind, cols), t = t)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/calibrate-linear.R tests/testthat/test-calibrate-linear.R
git commit -m "feat: add calibration constraint builder"
```

---

### Task 3: Newton solver (`.wf_lincal_group`)

**Files:**
- Modify: `R/calibrate-linear.R`
- Test: `tests/testthat/test-calibrate-linear.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-calibrate-linear.R`:

```r
test_that(".wf_lincal_group solves the GREG closed form by hand", {
  # sample a,a,b,b; base 1; total 4; margin a=3,b=1 -> weights 1.5,1.5,0.5,0.5
  X <- cbind(rep(1, 4), c(0, 0, 1, 1))
  t <- c(4, 1)
  d <- rep(1, 4)
  dist <- .wf_lincal_dist("linear", NULL)
  out <- .wf_lincal_group(X, d, t, dist, tol = 1e-10, max_iter = 100,
                          total = 4, g = "_all_")

  expect_true(out$converged)
  expect_equal(out$w, c(1.5, 1.5, 0.5, 0.5))
  expect_equal(out$iterations, 1)          # linear converges in one step
})

test_that(".wf_lincal_group logit keeps ratios within bounds and hits the target", {
  X <- cbind(rep(1, 4), c(0, 0, 1, 1))
  t <- c(4, 1)
  d <- rep(1, 4)
  dist <- .wf_lincal_dist("logit", c(0.3, 3))
  out <- .wf_lincal_group(X, d, t, dist, tol = 1e-10, max_iter = 100,
                          total = 4, g = "_all_")

  expect_true(out$converged)
  expect_true(all(out$ratio > 0.3 & out$ratio < 3))
  # margins: intercept and category-b constraint both met
  expect_equal(sum(out$w), 4, tolerance = 1e-8)
  expect_equal(sum(out$w[3:4]), 1, tolerance = 1e-8)
})

test_that(".wf_lincal_group aborts when bounds are infeasible", {
  # b units need mean 0.5 but a floor of 0.6 makes sum >= 1.2 > 1: infeasible
  X <- cbind(rep(1, 4), c(0, 0, 1, 1))
  t <- c(4, 1)
  d <- rep(1, 4)
  dist <- .wf_lincal_dist("logit", c(0.6, 3))
  expect_error(
    .wf_lincal_group(X, d, t, dist, tol = 1e-10, max_iter = 50,
                     total = 4, g = "_all_"),
    class = "wf_error_feasibility"
  )
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: FAIL — `could not find function ".wf_lincal_group"`.

- [ ] **Step 3: Implement `.wf_lincal_group`**

Append to `R/calibrate-linear.R`:

```r
#' Solve the calibration equations for one group by Newton iteration.
#'
#' @param X Constraint matrix (n x p).
#' @param d Base weights (length n).
#' @param t Target totals (length p; `t[1]` is the group total).
#' @param dist A `.wf_lincal_dist()` object.
#' @param tol Convergence tolerance on the max residual relative to `total`.
#' @param max_iter Iteration cap.
#' @param total Group total (for the relative residual).
#' @param g Group label (for error messages).
#' @keywords internal
#' @noRd
.wf_lincal_group <- function(X, d, t, dist, tol, max_iter, total, g) {
  lambda <- rep(0, ncol(X))
  u <- as.numeric(X %*% lambda)
  w <- d * dist$F(u)
  steps <- 0L
  converged <- FALSE
  maxr <- NA_real_
  repeat {
    resid <- t - as.numeric(t(X) %*% w)
    maxr <- max(abs(resid)) / total
    if (maxr < tol) {
      converged <- TRUE
      break
    }
    if (steps >= max_iter) break
    jac <- t(X) %*% (X * (d * dist$Fp(u)))
    step <- tryCatch(solve(jac, resid), error = function(e) NULL)
    if (is.null(step)) {
      wf_abort(
        sprintf("Group '%s': singular calibration system (empty category or collinear margins).", g),
        "wf_error_feasibility", list(group = g)
      )
    }
    lambda <- lambda + step
    steps <- steps + 1L
    u <- as.numeric(X %*% lambda)
    w <- d * dist$F(u)
  }
  if (!converged) {
    wf_abort(
      sprintf("Group '%s': calibration did not converge in %d iterations (max relative residual %.3g). Bounds may be too tight to meet the margins.",
              g, max_iter, maxr),
      "wf_error_feasibility", list(group = g, residual = maxr)
    )
  }
  list(w = w, iterations = steps, converged = TRUE,
       max_resid = maxr, ratio = dist$F(u))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/calibrate-linear.R tests/testthat/test-calibrate-linear.R
git commit -m "feat: add Newton calibration group solver"
```

---

### Task 4: Orchestration (`.wf_lincalibrate`) returning `wf_weights`

**Files:**
- Modify: `R/calibrate-linear.R`
- Test: `tests/testthat/test-calibrate-linear.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-calibrate-linear.R`:

```r
test_that(".wf_lincalibrate returns a wf_weights that hits every margin", {
  fixture <- make_weightflow_fixture()
  w <- .wf_lincalibrate(fixture$sample, fixture$target, distance = "linear",
                        method = "greg", id = "id")

  expect_s3_class(w, "wf_weights")
  expect_named(w$data, c("id", "group", "weight", "feature"))
  expect_equal(w$provenance$method, "greg")

  # province A female margin is reproduced
  s <- fixture$sample
  a_female <- sum(w$data$weight[s$province == "A" & s$gender == "female"])
  target_af <- fixture$target$groups[["A"]]$margins$gender[["female"]]
  expect_equal(a_female, target_af, tolerance = 1e-6)
})

test_that(".wf_lincalibrate respects init_weight", {
  fixture <- make_weightflow_fixture()
  s <- fixture$sample
  s$bw <- ifelse(s$gender == "female" & s$age == "young", 3, 1)

  uniform <- .wf_lincalibrate(s, fixture$target, distance = "linear",
                              method = "greg", id = "id")
  weighted <- .wf_lincalibrate(s, fixture$target, distance = "linear",
                               method = "greg", id = "id", init_weight = "bw")

  expect_false(isTRUE(all.equal(uniform$data$weight, weighted$data$weight)))
  # margins still reproduced under a non-uniform base
  a_female <- sum(weighted$data$weight[s$province == "A" & s$gender == "female"])
  expect_equal(a_female, fixture$target$groups[["A"]]$margins$gender[["female"]],
               tolerance = 1e-6)
})

test_that(".wf_lincalibrate drops NA rows with a warning and errors on demand", {
  fixture <- make_weightflow_fixture()
  s <- fixture$sample
  s$gender[1] <- NA

  expect_warning(
    .wf_lincalibrate(s, fixture$target, distance = "linear", method = "greg",
                     id = "id", na = "drop", precheck = FALSE),
    class = "wf_warning_data"
  )
  expect_error(
    .wf_lincalibrate(s, fixture$target, distance = "linear", method = "greg",
                     id = "id", na = "error", precheck = FALSE),
    class = "wf_error_schema"
  )
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: FAIL — `could not find function ".wf_lincalibrate"`.

- [ ] **Step 3: Implement `.wf_lincalibrate`**

Append to `R/calibrate-linear.R`:

```r
#' Calibrate weights by a linear or logit distance (engine behind wf_calibrate).
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param distance "linear" or "logit".
#' @param method Reported method label ("greg" or "logit").
#' @param bounds `c(L, U)` for logit.
#' @param init_weight Optional base-weight column.
#' @param na "drop" or "error".
#' @param id Optional id column.
#' @param tol Convergence tolerance.
#' @param max_iter Iteration cap.
#' @param precheck Run `wf_precheck()` first.
#' @keywords internal
#' @noRd
.wf_lincalibrate <- function(sample, target, distance, method,
                             bounds = NULL, init_weight = NULL,
                             na = c("drop", "error"), id = NULL,
                             tol = 1e-8, max_iter = 100, precheck = TRUE) {
  na <- match.arg(na)
  t0 <- Sys.time()

  if (precheck) {
    pc <- wf_precheck(sample, target, id = id, na = "drop")
    if (!pc$ok) {
      wf_abort(sprintf(
        "Precheck reports %d blocking issue(s). Inspect wf_precheck(sample, target) before calibrating.",
        sum(pc$issues$severity == "error")
      ), "wf_error_feasibility", list(precheck = pc))
    }
  }

  dvars <- target$dims
  for (d in dvars) {
    if (!d %in% names(sample)) {
      wf_abort(sprintf("Calibration dimension '%s' not found in sample.", d),
               "wf_error_schema", list(dim = d))
    }
  }

  na_mask <- rowSums(sapply(dvars, function(d) is.na(sample[[d]]))) > 0
  if (any(na_mask)) {
    if (na == "error") {
      wf_abort(sprintf("%d row(s) have NA in calibration dimensions.", sum(na_mask)),
               "wf_error_schema", list(n = sum(na_mask)))
    }
    wf_warn(sprintf("na='drop': removed %d row(s) with NA in calibration dimensions.",
                    sum(na_mask)), "wf_warning_data")
    sample <- sample[!na_mask, , drop = FALSE]
  }

  if (is.null(init_weight)) {
    iw <- rep(1, nrow(sample))
  } else {
    if (length(init_weight) != 1 || !is.character(init_weight) ||
        !init_weight %in% names(sample)) {
      wf_abort(sprintf("init_weight column '%s' not found in sample.",
                       as.character(init_weight)[1]),
               "wf_error_schema", list(init_weight = init_weight))
    }
    iw <- as.numeric(sample[[init_weight]])
    if (any(!is.finite(iw)) || any(iw < 0)) {
      wf_abort("init_weight must be non-negative and finite.",
               "wf_error_input", list(init_weight = init_weight))
    }
  }

  dist <- .wf_lincal_dist(distance, bounds)
  gkey <- .wf_group_keys(sample, target$by)
  ids <- if (is.null(id)) seq_len(nrow(sample)) else sample[[id]]

  res_rows <- list()
  logs <- list()
  achieved <- list()
  for (g in intersect(names(target$groups), unique(gkey))) {
    sel <- which(gkey == g)
    gr <- target$groups[[g]]
    sub <- sample[sel, , drop = FALSE]
    built <- .wf_lincal_build(sub, dvars, gr)
    fit <- .wf_lincal_group(built$X, iw[sel], built$t, dist,
                            tol, max_iter, gr$total, g)

    res_rows[[g]] <- data.frame(
      id = .chr(ids[sel]),
      group = g,
      weight = fit$w,
      feature = 1 / fit$w,
      stringsAsFactors = FALSE
    )
    logs[[g]] <- data.frame(
      group = g, n = length(sel), iterations = fit$iterations,
      converged = fit$converged, max_resid = fit$max_resid,
      ratio_min = min(fit$ratio), ratio_max = max(fit$ratio),
      stringsAsFactors = FALSE
    )
    achieved[[g]] <- lapply(dvars, function(d) {
      levs <- names(gr$margins[[d]])
      stats::setNames(
        vapply(levs, function(l) sum(fit$w[.chr(sub[[d]]) == l]), numeric(1)),
        levs
      )
    })
    names(achieved[[g]]) <- dvars
  }

  structure(list(
    data = do.call(rbind, res_rows),
    log = do.call(rbind, logs),
    achieved = achieved,
    provenance = list(
      method = method,
      distance = distance,
      bounds = bounds,
      init_weight = init_weight,
      na = na,
      dims = dvars,
      by = target$by,
      tol = tol,
      max_iter = max_iter,
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_lincal_package_version()
    )
  ), class = "wf_weights")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/calibrate-linear.R tests/testthat/test-calibrate-linear.R
git commit -m "feat: add linear/logit calibration orchestration"
```

---

### Task 5: Dispatcher wiring in `wf_calibrate()`

**Files:**
- Modify: `R/calibrate.R`
- Test: `tests/testthat/test-calibrate-linear.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-calibrate-linear.R`:

```r
test_that("wf_calibrate routes greg and logit to the calibration engine", {
  fixture <- make_weightflow_fixture()
  greg <- wf_calibrate(fixture$sample, fixture$target, method = "greg",
                       id = "id")
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(0.3, 3), id = "id")

  expect_equal(greg$provenance$method, "greg")
  expect_equal(logit$provenance$method, "logit")
  # logit ratios stay within bounds
  expect_true(all(logit$log$ratio_min >= 0.3 - 1e-9))
  expect_true(all(logit$log$ratio_max <= 3 + 1e-9))
})

test_that("wf_calibrate requires valid bounds for logit", {
  fixture <- make_weightflow_fixture()
  expect_error(
    wf_calibrate(fixture$sample, fixture$target, method = "logit", id = "id"),
    class = "wf_error_input"
  )
  expect_error(
    wf_calibrate(fixture$sample, fixture$target, method = "logit",
                 bounds = c(2, 0.5), id = "id"),
    class = "wf_error_input"
  )
})

test_that("wf_calibrate logit with loose bounds approximates raking", {
  fixture <- make_weightflow_fixture()
  raked <- wf_rake(fixture$sample, fixture$target, id = "id")
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(1e-6, 1e6), id = "id")
  m <- match(raked$data$id, logit$data$id)
  expect_equal(logit$data$weight[m], raked$data$weight, tolerance = 1e-4)
})

test_that("wf_calibrate still routes raking and poststrat unchanged", {
  fixture <- make_weightflow_fixture()
  raked <- wf_calibrate(fixture$sample, fixture$target, method = "raking",
                        id = "id")
  expect_equal(raked$provenance$method, "raking")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: FAIL — `wf_calibrate` aborts with "Unsupported calibration method 'greg'".

- [ ] **Step 3: Extend the dispatcher**

In `R/calibrate.R`, replace the body of `wf_calibrate` from the `supported`
definition through the end of the function with:

```r
  supported <- c("raking", "poststrat", "greg", "logit")
  if (length(method) != 1 || !method %in% supported) {
    shown <- if (length(method) == 0) "<empty>" else as.character(method[[1]])
    wf_abort(
      sprintf(
        "Unsupported calibration method '%s'. Supported methods: raking, poststrat, greg, logit.",
        shown
      ),
      "wf_error_input",
      list(method = method)
    )
  }

  if (method == "raking") {
    out <- wf_rake(sample, target, ...)
    out$provenance$method <- "raking"
    return(out)
  }

  if (method == "poststrat") {
    return(wf_poststrat(sample, target, ...))
  }

  bounds <- list(...)$bounds
  if (method == "logit") {
    if (is.null(bounds) || length(bounds) != 2 || !is.numeric(bounds) ||
        anyNA(bounds) || !(bounds[1] > 0 && bounds[1] < 1 && bounds[2] > 1)) {
      wf_abort(
        "method='logit' requires bounds = c(L, U) with 0 < L < 1 < U.",
        "wf_error_input", list(bounds = bounds)
      )
    }
  }

  distance <- if (method == "greg") "linear" else "logit"
  .wf_lincalibrate(sample, target, distance = distance, method = method, ...)
```

Also update the `@param method` roxygen line and add a `@param ...` note in
`R/calibrate.R` above `wf_calibrate`:

```r
#' @param method Calibration method: `"raking"`, `"poststrat"`, `"greg"`
#'   (linear GREG), or `"logit"` (bounded, requires `bounds = c(L, U)`).
#' @param ... Method-specific arguments. For `"greg"` / `"logit"`: `bounds`,
#'   `init_weight`, `na`, `id`, `tol`, `max_iter`, `precheck`.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/calibrate.R tests/testthat/test-calibrate-linear.R
git commit -m "feat: route greg/logit through wf_calibrate with bounds validation"
```

---

### Task 6: `print.wf_weights` branch for greg/logit

**Files:**
- Modify: `R/rake.R` (`print.wf_weights`)
- Test: `tests/testthat/test-calibrate-linear.R`

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-calibrate-linear.R`:

```r
test_that("print.wf_weights reports the calibration distance and bounds", {
  fixture <- make_weightflow_fixture()
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(0.3, 3), id = "id")
  expect_output(print(logit), "method: logit")
  expect_output(print(logit), "bounds")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: FAIL — the current print falls through to the raking branch (prints
`mode:`), not `method: logit`.

- [ ] **Step 3: Add the branch to `print.wf_weights`**

In `R/rake.R`, inside `print.wf_weights`, add this branch immediately after the
opening `{` (before the existing `propensity` branch):

```r
  if (!is.null(x$provenance$method) &&
      x$provenance$method %in% c("greg", "logit")) {
    bnd <- if (is.null(x$provenance$bounds)) "none" else
      sprintf("[%.3g, %.3g]", x$provenance$bounds[1], x$provenance$bounds[2])
    cat(sprintf(
      "<wf_weights>  %d unit(s) in %d group(s); method: %s (%s); bounds: %s\n",
      nrow(x$data), nrow(x$log), x$provenance$method,
      x$provenance$distance, bnd
    ))
    cat(sprintf(
      "  weight range [%.4g, %.4g]; converged: %d/%d; elapsed %.2fs\n",
      min(x$data$weight), max(x$data$weight),
      sum(x$log$converged), nrow(x$log), x$provenance$elapsed
    ))
    return(invisible(x))
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/rake.R tests/testthat/test-calibrate-linear.R
git commit -m "feat: print branch for greg/logit calibration weights"
```

---

### Task 7: Contract — compose and replicates refit

**Files:**
- Test: `tests/testthat/test-calibrate-linear.R`

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-calibrate-linear.R`:

```r
test_that("logit calibration composes and serves as a replicates refit", {
  fixture <- make_weightflow_fixture()
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(0.2, 5), id = "id")

  # composes with a second stage
  stage2 <- logit
  stage2$data$weight <- rep(2, nrow(stage2$data))
  stage2$data$feature <- 1 / stage2$data$weight
  composed <- wf_compose(cal = logit, adj = stage2)
  expect_s3_class(composed, "wf_weights")

  # serves as a wf_replicates refit (delete-one jackknife stays feasible)
  d <- fixture$sample
  d$y <- as.numeric(d$age == "young")
  refit <- function(data, weights) {
    data$.bw <- weights
    wf_calibrate(data, fixture$target, method = "logit", bounds = c(0.05, 20),
                 init_weight = ".bw", id = "id", precheck = FALSE)
  }
  reps <- wf_replicates(d, refit, method = "jackknife", id = "id")
  out <- wf_variance(reps, function(w, data) sum(w * data$y) / sum(w), d)
  expect_true(is.finite(out$table$se))
})
```

- [ ] **Step 2: Run the test**

Run: `Rscript -e 'devtools::test(filter = "calibrate-linear")'`
Expected: PASS. (If a jackknife replicate makes the bounds infeasible, widen the
refit's bounds; `c(0.05, 20)` is generous enough for this fixture.)

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-calibrate-linear.R
git commit -m "test: bounded calibration composes and drives variance"
```

---

### Task 8: Docs, version bump, and full check

**Files:**
- Modify: `NAMESPACE`, `man/` (generated), `DESCRIPTION`, `NEWS.md`, `README.md`

- [ ] **Step 1: Regenerate roxygen docs**

Run: `Rscript -e 'devtools::document()'`
Expected: `man/wf_calibrate.Rd` updated (new `method` levels and `...` note). No
new exports (the engine is internal). Run twice if link warnings appear.

- [ ] **Step 2: Bump the package version**

In `DESCRIPTION`, change `Version: 0.7.0` to `Version: 0.8.0`.

- [ ] **Step 3: Add the NEWS entry**

At the top of `NEWS.md`, above `# weightflow 0.7.0`, add:

```markdown
# weightflow 0.8.0

Bounded calibration. Adds a Deville-Sarndal calibration engine to
`wf_calibrate()` with linear (GREG) and bounded (logit) distances.

* Added `wf_calibrate(method = "greg")` for the linear GREG estimator.
* Added `wf_calibrate(method = "logit", bounds = c(L, U))` for calibration with
  weights bounded within `(L, U)` by construction, merging margin alignment and
  weight trimming into one step.
* Both calibrate to the existing `wf_target` margins, honour `init_weight`, and
  return the standard `wf_weights` so they compose and support replicate
  variance.
```

- [ ] **Step 4: Update the README**

In `README.md`, add a "Bounded Calibration" section after the "Variance &
Uncertainty" section:

```markdown
## Bounded Calibration

`wf_calibrate()` also offers general calibration beyond raking and
post-stratification. `method = "greg"` is the linear GREG estimator;
`method = "logit"` produces weights bounded within `bounds = c(L, U)` by
construction, merging margin alignment and weight trimming into one step.

```r
# weights bounded between 0.3x and 3x the base weight
w <- wf_calibrate(sample, target, method = "logit", bounds = c(0.3, 3),
                  init_weight = "design_w", id = "id")
w$log   # per-group convergence and realized weight-ratio range
```
```

And add a function-reference note after the `wf_calibrate()` row:

```markdown
| Calibrate | `wf_calibrate(method = "greg"/"logit")` | Linear GREG or bounded (logit) calibration to the target margins. |
```

Also bump the installation tarball reference to `weightflow_0.8.0.tar.gz`.

- [ ] **Step 5: Run the full suite and R CMD check**

Run: `Rscript -e 'devtools::test()'`
Expected: `FAIL 0`.

Run: `Rscript -e 'devtools::check(args = "--no-manual", error_on = "warning")'`
Expected: `0 errors | 0 warnings | 0 notes`.

- [ ] **Step 6: Commit**

```bash
git add man DESCRIPTION NEWS.md README.md R/
git commit -m "docs: document bounded calibration and bump to 0.8.0"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 = distance functions (linear + logit F/F'); Task 2 = constraint construction (intercept + dropped reference level); Task 3 = Newton solver with GREG closed-form, logit-bounds, and infeasibility/singular guards (`wf_error_feasibility`); Task 4 = orchestration returning `wf_weights`, `init_weight`, grouping, na drop/error (`wf_warning_data` / `wf_error_schema`); Task 5 = `wf_calibrate` routing + `bounds` validation (`wf_error_input`) + raking-limit + unchanged raking/poststrat routing; Task 6 = print branch; Task 7 = compose + replicates contract; Task 8 = docs/version/check.
- **Type consistency:** the distance object is `list(F, Fp)` throughout; `.wf_lincal_build` returns `list(X, t)`; `.wf_lincal_group` returns `list(w, iterations, converged, max_resid, ratio)`; `wf_weights` carries `$data` (id/group/weight/feature), `$log` (group/n/iterations/converged/max_resid/ratio_min/ratio_max), `$achieved`, `$provenance` (method/distance/bounds/init_weight/na/dims/by/tol/max_iter/...).
- **Deviations from spec:** `wf_calibrate` keeps its minimal formal signature and passes greg/logit args via `...` (documented) rather than adding them as formal parameters, to avoid collision with rake/poststrat; `na` supports `drop`/`error` only (no fractional), per the spec.
```
