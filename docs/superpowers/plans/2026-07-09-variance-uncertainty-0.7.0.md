# Variance & Uncertainty 0.7.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add replicate-weight variance (`wf_replicates()` + `wf_variance()`) that re-runs the calibration pipeline per replicate — so weighted estimates get standard errors and CIs including calibration uncertainty — plus an enabling `init_weight` argument on `wf_rake()`.

**Architecture:** Three replication generators (Rao–Wu bootstrap, stratified delete-one jackknife, Sylvester–Hadamard BRR) each emit a unit×R multiplier matrix plus `(scale, rscales)`. `wf_replicates()` perturbs base weights by those multipliers, re-calibrates each replicate through a user `refit` closure, and stores calibrated replicate weight columns. `wf_variance()` applies one unified rule `Var = scale·Σ rscales_r (θ̂_r − θ̂)²` to any estimator, so the three methods never fork the variance code. No core engine is restructured; raking gains a byte-identical-when-NULL `init_weight`.

**Tech Stack:** Base R (`stats::glm` not needed here; `sample`, `tabulate`, `stats::qnorm`, `stats::quantile`), the existing `wf_abort`/`wf_warn` helpers and `.chr` util, `testthat` edition 3, roxygen2/devtools.

**Reference:** Spec at `docs/superpowers/specs/2026-07-09-variance-uncertainty-design.md`. Idioms: `R/conditions.R` (`wf_abort`/`wf_warn`), `R/utils.R` (`.chr`), `R/compose.R` (`.wf_compose_package_version` pattern), `R/rake.R:44` (`.wf_expand_group`), `R/rake.R:110` (`wf_rake`), `R/rake.R:145` (group loop). Internal `.wf_*` helpers are callable directly in tests (devtools loads the package namespace).

**Test command:** `Rscript -e 'devtools::test(filter = "<name>")'`. Expect `FAIL 0`.

**Branch:** create `feat/variance-uncertainty-0.7.0` off `main` before Task 1.

---

### Task 1: `wf_rake(init_weight = )` enabling change

**Files:**
- Modify: `R/rake.R` (`.wf_expand_group` at line 44; `wf_rake` at line 110)
- Test: `tests/testthat/test-rake-init-weight.R`

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-rake-init-weight.R`:

```r
test_that("wf_rake init_weight = NULL reproduces the default result exactly", {
  fixture <- make_weightflow_fixture()
  a <- wf_rake(fixture$sample, fixture$target, id = "id")
  b <- wf_rake(fixture$sample, fixture$target, id = "id", init_weight = NULL)
  expect_equal(a$data$weight, b$data$weight)
})

test_that("wf_rake honors non-uniform init weights while matching margins", {
  fixture <- make_weightflow_fixture()
  s <- fixture$sample
  # Vary init WITHIN margin categories (young females only), so it is not
  # absorbed by the marginal gender/age calibration and actually shifts the
  # within-cell association.
  s$bw <- ifelse(s$gender == "female" & s$age == "young", 3, 1)

  uniform <- wf_rake(s, fixture$target, id = "id")
  weighted <- wf_rake(s, fixture$target, id = "id", init_weight = "bw")

  # init weights change the within-solution distribution
  expect_false(isTRUE(all.equal(uniform$data$weight, weighted$data$weight)))

  # but achieved gender totals still match (raking still hits its margins)
  female_uni <- sum(uniform$data$weight[s$gender == "female"])
  female_wtd <- sum(weighted$data$weight[s$gender == "female"])
  expect_equal(female_uni, female_wtd, tolerance = 1e-6)
})

test_that("wf_rake errors when init_weight column is missing", {
  fixture <- make_weightflow_fixture()
  expect_error(
    wf_rake(fixture$sample, fixture$target, id = "id", init_weight = "nope"),
    class = "wf_error_schema"
  )
})
```

Note: `make_weightflow_fixture()` is in `tests/testthat/helper-fixtures.R`; its
`$sample` has `id`, `province`, `gender`, `age` and its `$target` is grouped by
province with gender and age margins.

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "init-weight")'`
Expected: FAIL — `unused argument (init_weight = ...)`.

- [ ] **Step 3: Add the `init` parameter to `.wf_expand_group`**

In `R/rake.R`, change the `.wf_expand_group` signature and the two `w0`
assignments. Replace the current function body header:

```r
.wf_expand_group <- function(rows_chr, na_mask, margins, total) {
  n <- nrow(rows_chr)
  D <- ncol(rows_chr)
  base_w <- total / n
```

with:

```r
.wf_expand_group <- function(rows_chr, na_mask, margins, total, init = NULL) {
  n <- nrow(rows_chr)
  D <- ncol(rows_chr)
  base_w <- total / n
  rel <- if (is.null(init)) rep(1, n) else init / mean(init)
```

Then change the complete-case assignment from:

```r
    w0 <- rep(base_w, length(complete))
```

to:

```r
    w0 <- base_w * rel[complete]
```

And change the incomplete-block assignment from:

```r
      w0 <- c(w0, rep(base_w * share, times = length(rows)))
```

to:

```r
      w0 <- c(
        w0,
        base_w * rel[rep(rows, each = K)] * rep(share, times = length(rows))
      )
```

- [ ] **Step 4: Thread `init_weight` through `wf_rake`**

In `R/rake.R`, change the `wf_rake` signature (line 110) from:

```r
wf_rake <- function(sample, target, id = NULL,
                    na = c("fractional", "drop", "error"),
                    trim = NULL, trim_cycles = 4,
                    tol = 1e-6, max_iter = 200, precheck = TRUE) {
```

to:

```r
wf_rake <- function(sample, target, id = NULL,
                    na = c("fractional", "drop", "error"),
                    trim = NULL, trim_cycles = 4,
                    tol = 1e-6, max_iter = 200, precheck = TRUE,
                    init_weight = NULL) {
```

Immediately after the `sample <- sample[keep, , drop = FALSE]` block (the na="drop"
handling that ends near line 137) and before `gkey <- .wf_group_keys(...)`, insert
the init-weight extraction:

```r
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
    if (any(!is.finite(iw)) || any(iw <= 0)) {
      wf_abort("init_weight must be positive and finite.",
               "wf_error_input", list(init_weight = init_weight))
    }
  }
```

Then in the group loop (line 145), change the `.wf_expand_group` call from:

```r
    ex <- .wf_expand_group(rows, na_mask, gr$margins, gr$total)
```

to:

```r
    ex <- .wf_expand_group(rows, na_mask, gr$margins, gr$total, init = iw[sel])
```

Finally, add `init_weight = init_weight` to the `provenance` list in the returned
`wf_weights` (near line 236, alongside `trim = trim`):

```r
      init_weight = init_weight,
```

and document the new parameter by adding this roxygen line near the other
`@param` tags (before `@return A wf_weights object.`):

```r
#' @param init_weight Optional column of initial weights. If `NULL`, raking
#'   starts from uniform weights (unchanged behaviour).
```

- [ ] **Step 5: Run tests (new + regression)**

Run: `Rscript -e 'devtools::test(filter = "rake")'`
Expected: PASS — the new `init-weight` file and the existing `rake-diagnostics`
file both green (the NULL path is unchanged).

- [ ] **Step 6: Commit**

```bash
git add R/rake.R tests/testthat/test-rake-init-weight.R
git commit -m "feat: add init_weight to wf_rake for replicate base weights"
```

---

### Task 2: `.wf_design()` — strata/cluster resolution + nesting guard

**Files:**
- Create: `R/replicates.R`
- Test: `tests/testthat/test-replicates.R`

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-replicates.R`:

```r
make_design_data <- function() {
  data.frame(
    id = paste0("u", 1:8),
    stratum = c("A", "A", "A", "A", "B", "B", "B", "B"),
    psu = c("a1", "a1", "a2", "a2", "b1", "b1", "b2", "b2"),
    y = c(1, 0, 1, 1, 0, 0, 1, 0),
    stringsAsFactors = FALSE
  )
}

test_that(".wf_design resolves strata and clusters", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  expect_equal(des$n, 8)
  expect_setequal(des$strata, c("A", "B"))
  expect_setequal(des$psu[["A"]], c("a1", "a2"))
})

test_that(".wf_design defaults each row to its own PSU and a single stratum", {
  d <- make_design_data()
  des <- .wf_design(d, strata = NULL, clusters = NULL)
  expect_equal(des$strata, "1")
  expect_equal(length(des$psu[["1"]]), 8)
})

test_that(".wf_design rejects clusters that span strata", {
  d <- make_design_data()
  d$psu[5] <- "a1"  # a1 now appears in both stratum A and B
  expect_error(
    .wf_design(d, strata = "stratum", clusters = "psu"),
    class = "wf_error_design"
  )
})

test_that(".wf_design rejects missing columns", {
  d <- make_design_data()
  expect_error(.wf_design(d, strata = "nope", clusters = NULL),
               class = "wf_error_input")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: FAIL — `could not find function ".wf_design"`.

- [ ] **Step 3: Implement `.wf_design` and the version helper**

Create `R/replicates.R`:

```r
#' Return the loaded package version for provenance.
#'
#' @keywords internal
#' @noRd
.wf_replicates_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("weightflow")),
    error = function(e) "0.7.0"
  )
}

#' Resolve the sampling design (strata and PSUs) from data columns.
#'
#' @param data Input data frame.
#' @param strata Stratum column name or `NULL` (single stratum).
#' @param clusters PSU column name or `NULL` (each row is its own PSU).
#' @keywords internal
#' @noRd
.wf_design <- function(data, strata, clusters) {
  n <- nrow(data)
  if (!is.null(strata)) {
    if (length(strata) != 1 || !is.character(strata) ||
        !strata %in% names(data)) {
      wf_abort("`strata` must name a column in `data`.",
               "wf_error_input", list(strata = strata))
    }
    stratum <- .chr(data[[strata]])
  } else {
    stratum <- rep("1", n)
  }
  if (!is.null(clusters)) {
    if (length(clusters) != 1 || !is.character(clusters) ||
        !clusters %in% names(data)) {
      wf_abort("`clusters` must name a column in `data`.",
               "wf_error_input", list(clusters = clusters))
    }
    cluster <- .chr(data[[clusters]])
  } else {
    cluster <- as.character(seq_len(n))
  }

  pairs <- unique(data.frame(stratum = stratum, cluster = cluster,
                             stringsAsFactors = FALSE))
  dup <- pairs$cluster[duplicated(pairs$cluster)]
  if (length(dup) > 0) {
    wf_abort(
      sprintf("Clusters are not nested within strata: %s appear in >1 stratum.",
              paste(unique(dup), collapse = ", ")),
      "wf_error_design", list(clusters = unique(dup))
    )
  }

  strata_levels <- unique(stratum)
  psu <- lapply(strata_levels, function(h) unique(cluster[stratum == h]))
  names(psu) <- strata_levels
  list(n = n, stratum = stratum, cluster = cluster,
       strata = strata_levels, psu = psu)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/replicates.R tests/testthat/test-replicates.R
git commit -m "feat: add .wf_design strata/cluster resolver with nesting guard"
```

---

### Task 3: Rao–Wu bootstrap multiplier generator

**Files:**
- Modify: `R/replicates.R`
- Test: `tests/testthat/test-replicates.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-replicates.R`:

```r
test_that(".wf_boot_mult returns an n x R matrix with unit scale/rscales", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_boot_mult(des, R = 50, seed = 1)

  expect_equal(dim(gen$mult), c(8, 50))
  expect_equal(gen$scale, 1 / 50)
  expect_equal(gen$rscales, rep(1, 50))
  expect_true(all(gen$mult >= 0))
})

test_that(".wf_boot_mult multipliers are constant within a PSU", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_boot_mult(des, R = 10, seed = 1)
  # rows 1,2 are PSU a1; rows 3,4 are PSU a2
  expect_equal(gen$mult[1, ], gen$mult[2, ])
  expect_equal(gen$mult[3, ], gen$mult[4, ])
})

test_that(".wf_boot_mult per-stratum multiplier mean is about 1", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_boot_mult(des, R = 4000, seed = 42)
  stratum_A <- colMeans(gen$mult[1:4, ])  # 2 PSUs x 2 units, mean over units per rep
  expect_equal(mean(stratum_A), 1, tolerance = 0.05)
})

test_that(".wf_boot_mult is reproducible with a seed", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  g1 <- .wf_boot_mult(des, R = 20, seed = 7)
  g2 <- .wf_boot_mult(des, R = 20, seed = 7)
  expect_identical(g1$mult, g2$mult)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: FAIL — `could not find function ".wf_boot_mult"`.

- [ ] **Step 3: Implement `.wf_boot_mult`**

Append to `R/replicates.R`:

```r
#' Rao-Wu rescaled bootstrap multipliers.
#'
#' @param design A `.wf_design()` result.
#' @param R Number of replicates.
#' @param seed Optional integer seed.
#' @keywords internal
#' @noRd
.wf_boot_mult <- function(design, R, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  n <- design$n
  mult <- matrix(1, n, R)
  for (h in design$strata) {
    psus <- design$psu[[h]]
    nh <- length(psus)
    if (nh < 2) next
    units_by_psu <- lapply(psus, function(p) {
      which(design$stratum == h & design$cluster == p)
    })
    for (r in seq_len(R)) {
      draw <- sample.int(nh, nh - 1, replace = TRUE)
      counts <- tabulate(draw, nbins = nh)
      a <- (nh / (nh - 1)) * counts
      for (i in seq_len(nh)) {
        mult[units_by_psu[[i]], r] <- a[i]
      }
    }
  }
  list(mult = mult, scale = 1 / R, rscales = rep(1, R))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/replicates.R tests/testthat/test-replicates.R
git commit -m "feat: add Rao-Wu rescaled bootstrap multiplier generator"
```

---

### Task 4: Stratified delete-one jackknife generator

**Files:**
- Modify: `R/replicates.R`
- Test: `tests/testthat/test-replicates.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-replicates.R`:

```r
test_that(".wf_jack_mult emits one replicate per PSU with the right rescale", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_jack_mult(des)

  # 2 strata x 2 PSUs = 4 replicates
  expect_equal(ncol(gen$mult), 4)
  expect_equal(gen$scale, 1)
  expect_equal(gen$rscales, rep((2 - 1) / 2, 4))
})

test_that(".wf_jack_mult deletes exactly one PSU and rescales its stratum", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_jack_mult(des)

  # first replicate deletes PSU a1 (rows 1,2): 0 there, 2 for rows 3,4, 1 elsewhere
  col1 <- gen$mult[, 1]
  expect_equal(col1[1:2], c(0, 0))
  expect_equal(col1[3:4], c(2, 2))       # n_h/(n_h-1) = 2
  expect_equal(col1[5:8], rep(1, 4))     # other stratum untouched
})

test_that(".wf_jack_mult warns on a single-PSU stratum and skips it", {
  d <- make_design_data()
  d$stratum[8] <- "C"
  d$psu[8] <- "c1"                       # stratum C has 1 PSU
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  expect_warning(.wf_jack_mult(des), class = "wf_warning_quality")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: FAIL — `could not find function ".wf_jack_mult"`.

- [ ] **Step 3: Implement `.wf_jack_mult`**

Append to `R/replicates.R`:

```r
#' Stratified delete-one-PSU jackknife multipliers.
#'
#' @param design A `.wf_design()` result.
#' @keywords internal
#' @noRd
.wf_jack_mult <- function(design) {
  n <- design$n
  cols <- list()
  rscales <- numeric(0)
  for (h in design$strata) {
    psus <- design$psu[[h]]
    nh <- length(psus)
    in_h <- design$stratum == h
    if (nh < 2) {
      wf_warn(
        sprintf("Stratum '%s' has a single PSU; it cannot be jackknifed and contributes no replicate.", h),
        "wf_warning_quality", list(stratum = h)
      )
      next
    }
    for (p in psus) {
      m <- rep(1, n)
      m[in_h] <- nh / (nh - 1)
      m[in_h & design$cluster == p] <- 0
      cols[[length(cols) + 1]] <- m
      rscales <- c(rscales, (nh - 1) / nh)
    }
  }
  if (length(cols) == 0) {
    wf_abort("No stratum has >= 2 PSUs; jackknife has no replicates.",
             "wf_error_design")
  }
  list(mult = do.call(cbind, cols), scale = 1, rscales = rscales)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/replicates.R tests/testthat/test-replicates.R
git commit -m "feat: add stratified delete-one jackknife generator"
```

---

### Task 5: Hadamard matrix + BRR generator

**Files:**
- Modify: `R/replicates.R`
- Test: `tests/testthat/test-replicates.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-replicates.R`:

```r
test_that(".wf_hadamard builds an orthogonal +/-1 matrix of order a power of two", {
  H <- .wf_hadamard(3)         # next power of two >= 3 is 4
  expect_equal(dim(H), c(4, 4))
  expect_true(all(H %in% c(-1, 1)))
  expect_equal(t(H) %*% H, diag(4) * 4)
})

test_that(".wf_brr_mult assigns 2/0 within each 2-PSU stratum", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_brr_mult(des)

  expect_equal(gen$scale, 1 / ncol(gen$mult))
  expect_equal(gen$rscales, rep(1, ncol(gen$mult)))
  # rows 1,2 are PSU a1; rows 3,4 are PSU a2 (stratum A)
  for (r in seq_len(ncol(gen$mult))) {
    expect_true(all(gen$mult[1:4, r] %in% c(0, 2)))
    expect_equal(gen$mult[1, r], gen$mult[2, r])   # same PSU, same multiplier
    expect_equal(gen$mult[3, r], gen$mult[4, r])
    expect_equal(gen$mult[1, r] + gen$mult[3, r], 2)  # exactly one PSU selected
  }
})

test_that(".wf_brr_mult rejects a stratum without exactly 2 PSUs", {
  d <- make_design_data()
  d$psu[4] <- "a3"             # stratum A now has 3 PSUs
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  expect_error(.wf_brr_mult(des), class = "wf_error_design")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: FAIL — `could not find function ".wf_hadamard"`.

- [ ] **Step 3: Implement `.wf_hadamard` and `.wf_brr_mult`**

Append to `R/replicates.R`:

```r
#' Sylvester-construction Hadamard matrix of order >= `n` (a power of two).
#'
#' @param n Minimum order.
#' @keywords internal
#' @noRd
.wf_hadamard <- function(n) {
  k <- 1
  while (k < n) k <- k * 2
  H <- matrix(1, 1, 1)
  while (nrow(H) < k) {
    H <- rbind(cbind(H, H), cbind(H, -H))
  }
  H
}

#' Balanced Repeated Replication multipliers (standard half-sampling).
#'
#' @param design A `.wf_design()` result; every stratum must have 2 PSUs.
#' @keywords internal
#' @noRd
.wf_brr_mult <- function(design) {
  sizes <- vapply(design$psu, length, integer(1))
  bad <- design$strata[sizes != 2]
  if (length(bad) > 0) {
    wf_abort(
      sprintf("BRR requires exactly 2 PSUs per stratum; not met by: %s.",
              paste(bad, collapse = ", ")),
      "wf_error_design", list(strata = bad)
    )
  }
  H <- length(design$strata)
  hmat <- .wf_hadamard(H + 1)
  R <- nrow(hmat)
  n <- design$n
  mult <- matrix(1, n, R)
  for (hi in seq_along(design$strata)) {
    h <- design$strata[hi]
    psus <- design$psu[[h]]
    in_h <- design$stratum == h
    u1 <- in_h & design$cluster == psus[1]
    u2 <- in_h & design$cluster == psus[2]
    for (r in seq_len(R)) {
      if (hmat[r, hi + 1] > 0) {
        mult[u1, r] <- 2
        mult[u2, r] <- 0
      } else {
        mult[u1, r] <- 0
        mult[u2, r] <- 2
      }
    }
  }
  list(mult = mult, scale = 1 / R, rscales = rep(1, R))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/replicates.R tests/testthat/test-replicates.R
git commit -m "feat: add Hadamard matrix and BRR half-sample generator"
```

---

### Task 6: `wf_replicates()` orchestration + `wf_replicate_weights` object

**Files:**
- Modify: `R/replicates.R`
- Test: `tests/testthat/test-replicates.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-replicates.R`:

```r
# A trivial refit: no calibration, weights = base (so we can verify wiring).
trivial_refit <- function(data, weights) {
  structure(list(
    data = data.frame(id = data$id, group = "all",
                      weight = weights, feature = 1 / weights,
                      stringsAsFactors = FALSE)
  ), class = "wf_weights")
}

test_that("wf_replicates returns aligned base and replicate weights", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap",
                         R = 30, strata = "stratum", clusters = "psu",
                         id = "id", seed = 1)

  expect_s3_class(rep_w, "wf_replicate_weights")
  expect_equal(nrow(rep_w$base), 8)
  expect_equal(rep_w$base$id, d$id)
  expect_equal(dim(rep_w$replicates), c(8, 30))
  expect_equal(rep_w$base$weight, rep(1, 8))   # trivial refit, base = 1
  expect_equal(rep_w$provenance$method, "bootstrap")
  expect_equal(rep_w$provenance$seed, 1)
})

test_that("wf_replicates applies base_weight and perturbs it by the multipliers", {
  d <- make_design_data()
  d$bw <- rep(2, 8)
  rep_w <- wf_replicates(d, trivial_refit, method = "jackknife",
                         strata = "stratum", clusters = "psu",
                         id = "id", base_weight = "bw")
  # jackknife replicate 1 deletes PSU a1: rows 1,2 -> 0, rows 3,4 -> 2*2=4
  expect_equal(rep_w$replicates[1:2, 1], c(0, 0))
  expect_equal(rep_w$replicates[3:4, 1], c(4, 4))
})

test_that("wf_replicates errors when refit returns mismatched ids", {
  d <- make_design_data()
  bad_refit <- function(data, weights) {
    structure(list(
      data = data.frame(id = paste0("x", seq_len(nrow(data))),
                        group = "all", weight = weights,
                        feature = 1 / weights, stringsAsFactors = FALSE)
    ), class = "wf_weights")
  }
  expect_error(
    wf_replicates(d, bad_refit, method = "bootstrap", R = 3,
                  strata = "stratum", clusters = "psu", id = "id"),
    class = "wf_error_input"
  )
})

test_that("wf_replicates validates its inputs", {
  d <- make_design_data()
  expect_error(wf_replicates(d, "notfun", method = "bootstrap", id = "id"),
               class = "wf_error_input")
  expect_error(wf_replicates(d, trivial_refit, method = "bootstrap",
                             R = 0, id = "id"),
               class = "wf_error_input")
  expect_error(wf_replicates(d, trivial_refit, method = "bootstrap",
                             id = "missing"),
               class = "wf_error_input")
})

test_that("print.wf_replicate_weights reports method and replicate count", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap", R = 5,
                         strata = "stratum", clusters = "psu", id = "id",
                         seed = 1)
  expect_output(print(rep_w), "wf_replicate_weights")
  expect_output(print(rep_w), "bootstrap")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: FAIL — `could not find function "wf_replicates"`.

- [ ] **Step 3: Implement `wf_replicates` and its print method**

Append to `R/replicates.R`:

```r
#' Generate re-calibrated replicate weights for variance estimation.
#'
#' Perturbs base weights by bootstrap, jackknife, or BRR multipliers and
#' re-runs a calibration pipeline (`refit`) on each replicate, so the resulting
#' variance captures calibration uncertainty. Pair with [wf_variance()].
#'
#' @param data Input data frame (one row per unit).
#' @param refit A closure `function(data, weights) -> wf_weights` that re-runs
#'   the calibration pipeline using `weights` as the base/initial weights.
#' @param method Replication method.
#' @param R Number of bootstrap replicates (ignored for jackknife / BRR).
#' @param strata Optional stratum column name (single stratum if `NULL`).
#' @param clusters Optional PSU column name (each row is its own PSU if `NULL`).
#' @param id Optional id column aligning replicate weights (row order if `NULL`).
#' @param base_weight Optional starting base-weight column (all `1` if `NULL`).
#' @param seed Optional integer seed for the bootstrap draws.
#' @return A `wf_replicate_weights` object.
#' @export
wf_replicates <- function(data, refit,
                          method = c("bootstrap", "jackknife", "brr"),
                          R = 500, strata = NULL, clusters = NULL,
                          id = NULL, base_weight = NULL, seed = NULL) {
  if (!is.data.frame(data) || nrow(data) == 0) {
    wf_abort("`data` must be a non-empty data frame.", "wf_error_input")
  }
  if (!is.function(refit)) {
    wf_abort("`refit` must be a function(data, weights) returning a wf_weights.",
             "wf_error_input")
  }
  method <- match.arg(method)
  if (method == "bootstrap" &&
      (length(R) != 1 || !is.finite(R) || R < 1 || R != as.integer(R))) {
    wf_abort("`R` must be a positive integer.", "wf_error_input", list(R = R))
  }
  n <- nrow(data)
  if (!is.null(id)) {
    if (length(id) != 1 || !is.character(id) || !id %in% names(data)) {
      wf_abort("`id` must name a column in `data`.", "wf_error_input",
               list(id = id))
    }
    canon <- .chr(data[[id]])
  } else {
    canon <- as.character(seq_len(n))
  }
  if (anyDuplicated(canon)) {
    wf_abort("Unit ids are not unique.", "wf_error_input")
  }
  if (!is.null(base_weight)) {
    if (length(base_weight) != 1 || !is.character(base_weight) ||
        !base_weight %in% names(data)) {
      wf_abort("`base_weight` must name a column in `data`.", "wf_error_input",
               list(base_weight = base_weight))
    }
    base <- as.numeric(data[[base_weight]])
  } else {
    base <- rep(1, n)
  }
  if (any(!is.finite(base)) || any(base <= 0)) {
    wf_abort("`base_weight` must be positive and finite.", "wf_error_input")
  }

  design <- .wf_design(data, strata, clusters)
  t0 <- Sys.time()
  gen <- switch(
    method,
    bootstrap = .wf_boot_mult(design, R, seed),
    jackknife = .wf_jack_mult(design),
    brr = .wf_brr_mult(design)
  )

  align <- function(fit) {
    if (!inherits(fit, "wf_weights") || is.null(fit$data$id) ||
        is.null(fit$data$weight)) {
      wf_abort("`refit` must return a wf_weights with id and weight columns.",
               "wf_error_input")
    }
    fid <- .chr(fit$data$id)
    m <- match(canon, fid)
    if (length(fid) != n || anyNA(m)) {
      wf_abort("`refit` output ids do not match the input units.",
               "wf_error_input")
    }
    grp <- if (is.null(fit$data$group)) rep("all", n) else .chr(fit$data$group)[m]
    list(weight = as.numeric(fit$data$weight)[m], group = grp)
  }

  base_al <- align(refit(data, base))
  rg <- ncol(gen$mult)
  repw <- matrix(0, n, rg)
  for (r in seq_len(rg)) {
    repw[, r] <- align(refit(data, base * gen$mult[, r]))$weight
  }

  structure(list(
    base = data.frame(id = canon, group = base_al$group,
                      weight = base_al$weight, stringsAsFactors = FALSE),
    replicates = repw,
    scale = gen$scale,
    rscales = gen$rscales,
    method = method,
    design = list(strata = strata, clusters = clusters,
                  n_strata = length(design$strata), R = rg),
    provenance = list(
      method = method, R = rg, seed = seed,
      strata = strata, clusters = clusters, base_weight = base_weight,
      created = t0, elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_replicates_package_version()
    )
  ), class = "wf_replicate_weights")
}

#' Print replicate weights
#'
#' @param x A `wf_replicate_weights` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_replicate_weights <- function(x, ...) {
  cat(sprintf("<wf_replicate_weights>  %d unit(s); method: %s; %d replicate(s)\n",
              nrow(x$base), x$method, ncol(x$replicates)))
  cat(sprintf("  design: %d stratum(s); scale %.4g; elapsed %.2fs\n",
              x$design$n_strata, x$scale, x$provenance$elapsed))
  invisible(x)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "replicates")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/replicates.R tests/testthat/test-replicates.R
git commit -m "feat: add wf_replicates orchestration and wf_replicate_weights"
```

---

### Task 7: `wf_variance()` + result object

**Files:**
- Create: `R/variance.R`
- Test: `tests/testthat/test-variance.R`

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-variance.R`:

```r
trivial_refit <- function(data, weights) {
  structure(list(
    data = data.frame(id = data$id, group = "all",
                      weight = weights, feature = 1 / weights,
                      stringsAsFactors = FALSE)
  ), class = "wf_weights")
}

wmean_y <- function(weights, data) sum(weights * data$y) / sum(weights)

test_that("wf_variance reproduces the unified formula on a bootstrap fixture", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap", R = 100,
                         strata = "stratum", clusters = "psu", id = "id",
                         seed = 3)
  out <- wf_variance(rep_w, wmean_y, d)

  theta <- wmean_y(rep_w$base$weight, d)
  tr <- vapply(seq_len(ncol(rep_w$replicates)),
               function(r) wmean_y(rep_w$replicates[, r], d), numeric(1))
  expected_var <- rep_w$scale * sum(rep_w$rscales * (tr - theta)^2)

  expect_equal(out$table$estimate, theta)
  expect_equal(out$table$variance, expected_var)
  expect_equal(out$table$se, sqrt(expected_var))
})

test_that("wf_variance matches a hand-computed jackknife variance", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "jackknife",
                         strata = "stratum", clusters = "psu", id = "id")
  out <- wf_variance(rep_w, wmean_y, d)

  theta <- wmean_y(rep_w$base$weight, d)
  tr <- vapply(seq_len(ncol(rep_w$replicates)),
               function(r) wmean_y(rep_w$replicates[, r], d), numeric(1))
  expected_var <- sum(rep_w$rscales * (tr - theta)^2)  # scale = 1
  expect_equal(out$table$variance, expected_var)
})

test_that("wf_variance supports vector (subgroup) estimators", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap", R = 50,
                         strata = "stratum", clusters = "psu", id = "id",
                         seed = 5)
  by_stratum <- function(weights, data) {
    c(A = sum(weights[data$stratum == "A"] * data$y[data$stratum == "A"]) /
          sum(weights[data$stratum == "A"]),
      B = sum(weights[data$stratum == "B"] * data$y[data$stratum == "B"]) /
          sum(weights[data$stratum == "B"]))
  }
  out <- wf_variance(rep_w, by_stratum, d)
  expect_equal(nrow(out$table), 2)
  expect_equal(out$table$quantity, c("A", "B"))
})

test_that("wf_variance builds normal and percentile CIs", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap", R = 200,
                         strata = "stratum", clusters = "psu", id = "id",
                         seed = 9)
  normal <- wf_variance(rep_w, wmean_y, d, ci = "normal")
  pctile <- wf_variance(rep_w, wmean_y, d, ci = "percentile")

  expect_true(normal$table$ci_lower < normal$table$estimate)
  expect_true(pctile$table$ci_upper > pctile$table$estimate)
  expect_equal(as.data.frame(normal), normal$table)
})

test_that("wf_variance rejects percentile CI for non-bootstrap replicates", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "jackknife",
                         strata = "stratum", clusters = "psu", id = "id")
  expect_error(wf_variance(rep_w, wmean_y, d, ci = "percentile"),
               class = "wf_error_input")
})

test_that("wf_variance validates its inputs", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap", R = 10,
                         strata = "stratum", clusters = "psu", id = "id",
                         seed = 1)
  expect_error(wf_variance(list(), wmean_y, d), class = "wf_error_input")
  expect_error(wf_variance(rep_w, "notfun", d), class = "wf_error_input")
  expect_error(wf_variance(rep_w, wmean_y, d, level = 1.5),
               class = "wf_error_input")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "variance")'`
Expected: FAIL — `could not find function "wf_variance"`.

- [ ] **Step 3: Implement `wf_variance`, its print and as.data.frame**

Create `R/variance.R`:

```r
#' Combine replicate weights and an estimator into a variance and CI.
#'
#' Applies the unified replication rule
#' `Var = scale * sum_r rscales_r * (theta_r - theta)^2` to any estimator, using
#' the `(scale, rscales)` stored by [wf_replicates()].
#'
#' @param replicates A `wf_replicate_weights` object.
#' @param estimator A closure `function(weights, data) -> numeric` (scalar or
#'   named vector).
#' @param data The data frame the estimator reads.
#' @param level Confidence level in `(0, 1)`.
#' @param ci Interval type: `"normal"` or (bootstrap only) `"percentile"`.
#' @return A `wf_variance_result` object.
#' @export
wf_variance <- function(replicates, estimator, data, level = 0.95,
                        ci = c("normal", "percentile")) {
  if (!inherits(replicates, "wf_replicate_weights")) {
    wf_abort("`replicates` must be a wf_replicate_weights object.",
             "wf_error_input")
  }
  if (!is.function(estimator)) {
    wf_abort("`estimator` must be a function(weights, data).", "wf_error_input")
  }
  if (length(level) != 1 || !is.finite(level) || level <= 0 || level >= 1) {
    wf_abort("`level` must be a single number in (0, 1).", "wf_error_input",
             list(level = level))
  }
  ci <- match.arg(ci)
  if (ci == "percentile" && replicates$method != "bootstrap") {
    wf_abort("`ci = 'percentile'` is only valid for bootstrap replicates.",
             "wf_error_input", list(method = replicates$method))
  }

  base_est <- estimator(replicates$base$weight, data)
  nm <- names(base_est)
  theta <- as.numeric(base_est)
  q <- length(theta)
  if (q == 0) {
    wf_abort("`estimator` returned a length-zero result.", "wf_error_input")
  }

  R <- ncol(replicates$replicates)
  tr <- matrix(NA_real_, q, R)
  for (r in seq_len(R)) {
    v <- as.numeric(estimator(replicates$replicates[, r], data))
    if (length(v) != q) {
      wf_abort("`estimator` returned inconsistent length across replicates.",
               "wf_error_input")
    }
    tr[, r] <- v
  }

  dev2 <- (tr - theta)^2
  variance <- replicates$scale * as.numeric(dev2 %*% replicates$rscales)
  se <- sqrt(variance)

  if (is.null(nm)) {
    nm <- if (q == 1) "estimate" else as.character(seq_len(q))
  }

  if (ci == "normal") {
    z <- stats::qnorm(1 - (1 - level) / 2)
    lo <- theta - z * se
    hi <- theta + z * se
  } else {
    a <- (1 - level) / 2
    lo <- vapply(seq_len(q),
                 function(i) stats::quantile(tr[i, ], a, names = FALSE),
                 numeric(1))
    hi <- vapply(seq_len(q),
                 function(i) stats::quantile(tr[i, ], 1 - a, names = FALSE),
                 numeric(1))
  }

  structure(list(
    table = data.frame(
      quantity = nm, estimate = theta, variance = variance, se = se,
      ci_lower = lo, ci_upper = hi, stringsAsFactors = FALSE
    ),
    provenance = list(method = replicates$method, level = level,
                      ci = ci, R = R)
  ), class = "wf_variance_result")
}

#' Print a variance result
#'
#' @param x A `wf_variance_result` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_variance_result <- function(x, ...) {
  cat(sprintf("<wf_variance_result>  method: %s; %d replicate(s); %.0f%% %s CI\n",
              x$provenance$method, x$provenance$R,
              100 * x$provenance$level, x$provenance$ci))
  print(x$table, row.names = FALSE)
  invisible(x)
}

#' Coerce a variance result to a data frame
#'
#' @param x A `wf_variance_result` object.
#' @param ... Unused.
#' @return The result table as a data frame.
#' @export
as.data.frame.wf_variance_result <- function(x, ...) {
  x$table
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "variance")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/variance.R tests/testthat/test-variance.R
git commit -m "feat: add wf_variance with unified replication combining rule"
```

---

### Task 8: End-to-end integration with a real calibration refit

**Files:**
- Test: `tests/testthat/test-variance.R`

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-variance.R`:

```r
test_that("wf_replicates + wf_variance run through a real raking refit", {
  fixture <- make_weightflow_fixture()
  d <- fixture$sample
  d$y <- as.numeric(d$age == "young")

  refit <- function(data, weights) {
    data$.bw <- weights
    wf_rake(data, fixture$target, id = "id", init_weight = ".bw",
            precheck = FALSE)
  }

  rep_w <- wf_replicates(d, refit, method = "bootstrap", R = 40,
                         id = "id", seed = 11)
  out <- wf_variance(rep_w, function(w, data) sum(w * data$y) / sum(w), d)

  expect_s3_class(out, "wf_variance_result")
  expect_true(is.finite(out$table$se))
  expect_true(out$table$se >= 0)
  expect_true(out$table$ci_lower <= out$table$estimate)
})
```

Note: `make_weightflow_fixture()` returns `$sample` (with `id` and `age`) and
`$target`. The refit re-rakes each replicate's base weights, so this test proves
calibration uncertainty is captured end to end.

- [ ] **Step 2: Run the test**

Run: `Rscript -e 'devtools::test(filter = "variance")'`
Expected: PASS. If raking rejects `precheck = FALSE` or the fixture shape differs,
fix the refit closure to match the real `wf_rake` contract before proceeding.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-variance.R
git commit -m "test: end-to-end variance through a raking refit"
```

---

### Task 9: Docs, exports, version bump, and full check

**Files:**
- Modify: `NAMESPACE`, `man/` (generated), `DESCRIPTION`, `NEWS.md`, `README.md`

- [ ] **Step 1: Regenerate roxygen docs and exports**

Run: `Rscript -e 'devtools::document()'`
Expected: `NAMESPACE` gains `export(wf_replicates)`, `export(wf_variance)`,
`S3method(print, wf_replicate_weights)`, `S3method(print, wf_variance_result)`,
`S3method(as.data.frame, wf_variance_result)`; `man/wf_replicates.Rd` and
`man/wf_variance.Rd` created; `man/wf_rake.Rd` updated with `init_weight`. Run it
a second time if cross-reference link warnings appear on the first pass.

- [ ] **Step 2: Bump the package version**

In `DESCRIPTION`, change `Version: 0.6.0` to `Version: 0.7.0`.

- [ ] **Step 3: Add the NEWS entry**

At the top of `NEWS.md`, above `# weightflow 0.6.0`, add:

```markdown
# weightflow 0.7.0

Variance and uncertainty. Adds replicate-weight variance that re-runs the
calibration pipeline per replicate, so estimates carry standard errors and
confidence intervals including calibration uncertainty.

* Added `wf_replicates()` to generate re-calibrated replicate weights via
  Rao-Wu bootstrap, stratified delete-one jackknife, or BRR, driven by a user
  refit closure.
* Added `wf_variance()` to combine replicate weights and an estimator into an
  estimate, variance, standard error, and normal or percentile confidence
  interval, using one unified combining rule across methods.
* Added an `init_weight` argument to `wf_rake()` so raking can consume replicate
  base weights (unchanged behaviour when `NULL`).
```

- [ ] **Step 4: Update the README**

In `README.md`, add a "Variance & Uncertainty" section after the
"Non-Probability Correction" section:

```markdown
## Variance & Uncertainty

Any weighted estimate can carry a standard error and confidence interval that
include calibration uncertainty, via replicate weights. `wf_replicates()`
perturbs base weights (Rao-Wu bootstrap, jackknife, or BRR) and re-runs the
calibration pipeline on each replicate through a `refit` closure;
`wf_variance()` combines them with an estimator into an estimate, SE, and CI.

```r
refit <- function(data, weights) {
  data$.bw <- weights
  wf_rake(data, target, id = "id", init_weight = ".bw")
}

reps <- wf_replicates(sample, refit, method = "bootstrap", R = 500,
                      strata = "stratum", clusters = "psu", id = "id",
                      seed = 1)
wf_variance(reps, function(w, d) sum(w * d$y) / sum(w), sample)
```
```

And add function-reference rows after the Fusion / Propensity rows:

```markdown
| Variance | `wf_replicates()` | Generate re-calibrated bootstrap/jackknife/BRR replicate weights. |
| Variance | `wf_variance()` | Combine replicate weights and an estimator into an estimate, SE, and CI. |
```

Also bump the installation tarball reference from `weightflow_0.6.0.tar.gz` to
`weightflow_0.7.0.tar.gz`.

- [ ] **Step 5: Run the full suite and R CMD check**

Run: `Rscript -e 'devtools::test()'`
Expected: `FAIL 0`.

Run: `Rscript -e 'devtools::check(args = "--no-manual", error_on = "warning")'`
Expected: `0 errors | 0 warnings | 0 notes`.

- [ ] **Step 6: Commit**

```bash
git add NAMESPACE man DESCRIPTION NEWS.md README.md R/
git commit -m "docs: export variance API and bump to 0.7.0"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 = `wf_rake(init_weight)` enabling change; Tasks 2–5 = the design resolver and the three generators with their `(scale, rscales)`; Task 6 = `wf_replicates()` orchestration, id alignment, refit-mismatch guard, and the `wf_replicate_weights` object/print; Task 7 = `wf_variance()`, the unified formula, vector estimators, normal/percentile CIs, and the result object; Task 8 = end-to-end calibration-uncertainty proof through a raking refit; Task 9 = exports, NEWS/DESCRIPTION/README, check. `wf_error_design` is exercised in Tasks 2 and 5; `wf_warning_quality` (single-PSU jackknife) in Task 4.
- **Type consistency:** generators uniformly return `list(mult, scale, rscales)`; `wf_replicate_weights` carries `$base` (id/group/weight), `$replicates` (matrix), `$scale`, `$rscales`, `$method`, `$design`, `$provenance`; `wf_variance_result` carries `$table` (quantity/estimate/variance/se/ci_lower/ci_upper) and `$provenance`. The `refit` closure signature `function(data, weights)` is identical in Tasks 6, 7, 8.
- **Deviations from roadmap:** BRR is standard half-sampling (no Fay `rho`); `parallel` is reserved/undocumented-as-implemented; the replay mechanism is the user `refit` closure (no re-executable `wf_compose` recipe), per the approved spec.
```
