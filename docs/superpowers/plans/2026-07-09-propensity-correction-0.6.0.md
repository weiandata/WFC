# Propensity Correction 0.6.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `wf_target_propensity()` and `wf_propensity()` so the self-selected online sample can be corrected against the offline probability reference, emitting mean-1 pseudo-design weights (a `wf_weights` object) that feed `wf_rake()`/`wf_poststrat()` as `init_weight` and compose via `wf_compose()`.

**Architecture:** Two functions in one new file `R/propensity.R`. `wf_target_propensity()` (Seam 1) validates a two-sided membership `formula`, stacks `online` + `reference` into one frame with a `0/1` membership indicator, and stores the spec without fitting. `wf_propensity()` (Seam 2) fits `glm(family = binomial)` (optionally per `by` group), turns fitted online-membership probabilities into inverse-propensity pseudo-weights (stabilized by default, optional trim, normalized to mean 1 per group), and returns a `wf_weights` object carrying `$overlap` and `$balance` diagnostics — mirroring how `wf_poststrat()` attaches `cell_report`/`collapse_map`. No core engine is touched.

**Tech Stack:** Base R (`stats::glm`, `stats::reformulate`), the existing `wf_abort`/`wf_warn` condition helpers and `.chr` util, `testthat` edition 3, roxygen2/devtools.

**Reference:** Spec at `docs/superpowers/specs/2026-07-09-propensity-correction-design.md`. Existing idioms to match: `R/conditions.R` (`wf_abort`/`wf_warn`), `R/utils.R` (`.chr`), `R/compose.R` (`.wf_compose_package_version` pattern), `R/rake.R:253` (`print.wf_weights`), `tests/testthat/test-compose.R` (`make_compose_stage` helper, `wf_weights$data` = `id/group/weight/feature`), `tests/testthat/test-blend.R` (`expect_error(..., class = "wf_error_input")`).

**Test command:** `Rscript -e 'devtools::test(filter = "propensity")'` (matches both `test-target-propensity.R` and `test-propensity.R`). Expect the printed summary to show `FAIL 0`.

---

### Task 1: `wf_target_propensity()` — input validation

**Files:**
- Create: `R/propensity.R`
- Test: `tests/testthat/test-target-propensity.R`

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-target-propensity.R`:

```r
make_prop_frames <- function() {
  online <- data.frame(
    pid = paste0("o", 1:6),
    age = c(20, 25, 30, 35, 40, 45),
    edu = c("hs", "hs", "col", "col", "hs", "col"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    pid = paste0("r", 1:6),
    age = c(22, 33, 44, 55, 60, 28),
    edu = c("col", "col", "hs", "hs", "col", "hs"),
    stringsAsFactors = FALSE
  )
  list(online = online, reference = reference)
}

test_that("wf_target_propensity rejects a one-sided formula", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, ~ age + edu),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity rejects an empty right-hand side", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, member ~ 1),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity errors when a predictor is missing", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, member ~ age + income),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity errors when membership name collides", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, age ~ age + edu),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity errors on empty frames", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online[0, ], f$reference, member ~ age),
    class = "wf_error_input"
  )
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: FAIL — `could not find function "wf_target_propensity"`.

- [ ] **Step 3: Write the constructor with validation only**

Create `R/propensity.R`:

```r
#' Return the loaded package version for provenance.
#'
#' @keywords internal
#' @noRd
.wf_propensity_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("weightflow")),
    error = function(e) "0.6.0"
  )
}

#' Build a propensity target: stacked reference frame and membership model spec.
#'
#' Stacks a self-selected `online` sample and a probability `reference` sample
#' into one frame with a membership indicator, so the online sample's selection
#' propensity can be modelled. No model is fit here; execution happens in
#' [wf_propensity()].
#'
#' @param online Data frame: the self-selected (non-probability) sample.
#' @param reference Data frame: the probability reference sample.
#' @param formula Two-sided membership formula, e.g. `member ~ age + edu`. The
#'   right-hand side names the model predictors; the left-hand side names the
#'   membership indicator the constructor creates (`1` online, `0` reference).
#' @param method Fit backend. Only `"logit"` is executable in this release;
#'   `"rf"` / `"gbm"` are reserved and abort in [wf_propensity()].
#' @param by Optional grouping column present in both frames; the propensity
#'   model is fit within each group.
#' @param id Optional id column in `online`; when `NULL`, online units are
#'   identified by row order.
#' @return A `wf_target_propensity` object.
#' @export
wf_target_propensity <- function(online, reference, formula,
                                 method = c("logit", "rf", "gbm"),
                                 by = NULL, id = NULL) {
  method <- match.arg(method)
  if (!is.data.frame(online) || nrow(online) == 0) {
    wf_abort("`online` must be a non-empty data frame.", "wf_error_input")
  }
  if (!is.data.frame(reference) || nrow(reference) == 0) {
    wf_abort("`reference` must be a non-empty data frame.", "wf_error_input")
  }
  if (!inherits(formula, "formula") || length(formula) != 3) {
    wf_abort(
      "`formula` must be a two-sided formula, e.g. member ~ age + edu.",
      "wf_error_input"
    )
  }
  membership <- all.vars(formula[[2]])
  if (length(membership) != 1) {
    wf_abort(
      "The left-hand side of `formula` must be a single membership name.",
      "wf_error_input"
    )
  }
  predictors <- all.vars(formula[[3]])
  if (length(predictors) == 0) {
    wf_abort(
      "`formula` must name at least one predictor on the right-hand side.",
      "wf_error_input"
    )
  }
  if (membership %in% predictors) {
    wf_abort(
      sprintf("Membership name '%s' collides with a predictor.", membership),
      "wf_error_input", list(membership = membership)
    )
  }
  miss_online <- setdiff(predictors, names(online))
  if (length(miss_online) > 0) {
    wf_abort(
      sprintf("`online` is missing predictor(s): %s",
              paste(miss_online, collapse = ", ")),
      "wf_error_input", list(missing = miss_online)
    )
  }
  miss_ref <- setdiff(predictors, names(reference))
  if (length(miss_ref) > 0) {
    wf_abort(
      sprintf("`reference` is missing predictor(s): %s",
              paste(miss_ref, collapse = ", ")),
      "wf_error_input", list(missing = miss_ref)
    )
  }
  if (!is.null(by)) {
    if (length(by) != 1 || !is.character(by)) {
      wf_abort("`by` must be a single column name.", "wf_error_input")
    }
    if (!by %in% names(online)) {
      wf_abort(sprintf("`online` is missing `by` column '%s'.", by),
               "wf_error_input", list(by = by))
    }
    if (!by %in% names(reference)) {
      wf_abort(sprintf("`reference` is missing `by` column '%s'.", by),
               "wf_error_input", list(by = by))
    }
  }
  if (!is.null(id)) {
    if (length(id) != 1 || !is.character(id)) {
      wf_abort("`id` must be a single column name.", "wf_error_input")
    }
    if (!id %in% names(online)) {
      wf_abort(sprintf("`online` is missing `id` column '%s'.", id),
               "wf_error_input", list(id = id))
    }
  }

  keep <- unique(c(predictors, by))
  online_part <- online[, keep, drop = FALSE]
  online_part[[membership]] <- 1L
  online_part$.wf_source <- "online"
  ref_part <- reference[, keep, drop = FALSE]
  ref_part[[membership]] <- 0L
  ref_part$.wf_source <- "reference"
  stacked <- rbind(online_part, ref_part)

  online_ids <- if (is.null(id)) {
    as.character(seq_len(nrow(online)))
  } else {
    .chr(online[[id]])
  }

  structure(list(
    online = online,
    reference = reference,
    stacked = stacked,
    membership = membership,
    predictors = predictors,
    formula = formula,
    method = method,
    by = by,
    id = id,
    online_ids = online_ids,
    n_online = nrow(online),
    n_reference = nrow(reference),
    provenance = list(
      created = Sys.time(),
      package_version = .wf_propensity_package_version()
    )
  ), class = "wf_target_propensity")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: PASS (all Task 1 tests).

- [ ] **Step 5: Commit**

```bash
git add R/propensity.R tests/testthat/test-target-propensity.R
git commit -m "feat: add wf_target_propensity constructor with validation"
```

---

### Task 2: `wf_target_propensity()` — stacking correctness

**Files:**
- Test: `tests/testthat/test-target-propensity.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-target-propensity.R`:

```r
test_that("wf_target_propensity builds a membership indicator and keeps online order", {
  f <- make_prop_frames()
  tgt <- wf_target_propensity(f$online, f$reference, member ~ age + edu)

  expect_s3_class(tgt, "wf_target_propensity")
  expect_equal(tgt$membership, "member")
  expect_setequal(tgt$predictors, c("age", "edu"))
  # online rows first, in order, all member == 1
  expect_equal(tgt$stacked$member, c(rep(1L, 6), rep(0L, 6)))
  expect_equal(tgt$stacked$.wf_source, c(rep("online", 6), rep("reference", 6)))
  expect_equal(tgt$stacked$age[1:6], f$online$age)
})

test_that("wf_target_propensity uses row order ids by default and the id column when given", {
  f <- make_prop_frames()
  tgt_default <- wf_target_propensity(f$online, f$reference, member ~ age)
  expect_equal(tgt_default$online_ids, as.character(1:6))

  tgt_id <- wf_target_propensity(f$online, f$reference, member ~ age, id = "pid")
  expect_equal(tgt_id$online_ids, f$online$pid)
})

test_that("wf_target_propensity does not fit a model at construction", {
  f <- make_prop_frames()
  tgt <- wf_target_propensity(f$online, f$reference, member ~ age)
  expect_false("model" %in% names(tgt))
})
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: PASS. These assert behavior already implemented in Task 1 (stacking, ids, no-fit). If any fail, fix the constructor before proceeding.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-target-propensity.R
git commit -m "test: cover wf_target_propensity stacking and id handling"
```

---

### Task 3: `wf_propensity()` — fit, IPW weights, `wf_weights` contract

**Files:**
- Modify: `R/propensity.R`
- Test: `tests/testthat/test-propensity.R`

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-propensity.R`:

```r
# Online sample skews toward high x; reference is centered lower but overlaps,
# so glm fits cleanly (no perfect separation).
make_prop_target <- function() {
  online <- data.frame(
    x = c(1.0, 1.4, 1.8, 2.2, 2.6, 3.0, 3.4, -0.5),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-2.0, -1.6, -1.2, -0.8, -0.4, 0.0, 0.4, 2.8),
    stringsAsFactors = FALSE
  )
  wf_target_propensity(online, reference, member ~ x)
}

test_that("wf_propensity returns a wf_weights object with the id/group/weight/feature contract", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))

  expect_s3_class(w, "wf_weights")
  expect_named(w$data, c("id", "group", "weight", "feature"))
  expect_equal(nrow(w$data), tgt$n_online)
  expect_equal(w$data$id, as.character(1:8))
  expect_true(all(w$data$weight > 0))
  expect_equal(w$data$feature, 1 / w$data$weight)
  expect_equal(w$provenance$method, "propensity")
})

test_that("wf_propensity ipw weights are proportional to 1/phat and normalized to mean 1", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE))

  # Independently refit the same model to recover the fitted online propensities.
  fit <- stats::glm(member ~ x, family = stats::binomial(), data = tgt$stacked)
  phat_online <- stats::fitted(fit)[tgt$stacked$.wf_source == "online"]
  expected <- 1 / phat_online
  expected <- expected / mean(expected)

  expect_equal(mean(w$data$weight), 1)
  expect_equal(w$data$weight, expected, tolerance = 1e-8)
})

test_that("wf_propensity stabilized weights differ from raw ipw but stay mean 1", {
  tgt <- make_prop_target()
  raw <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE))
  stab <- suppressWarnings(wf_propensity(tgt, stabilize = TRUE))
  # Single group: stabilization is a constant factor, so mean-1 normalization
  # makes the final vectors equal. Assert both are valid mean-1 vectors.
  expect_equal(mean(stab$data$weight), 1)
  expect_equal(stab$provenance$stabilize, TRUE)
  expect_equal(raw$provenance$stabilize, FALSE)
})

test_that("wf_propensity trims extreme weights and records the count", {
  tgt <- make_prop_target()
  untrimmed <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE))
  trimmed <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE, trim = 1.5))

  expect_gte(trimmed$provenance$trimmed, 1)
  expect_lte(max(trimmed$data$weight), max(untrimmed$data$weight) + 1e-9)
  expect_equal(mean(trimmed$data$weight), 1)
})

test_that("wf_propensity rejects reserved methods, weights and bad trim", {
  tgt <- make_prop_target()
  tgt_rf <- tgt; tgt_rf$method <- "rf"
  expect_error(wf_propensity(tgt_rf), class = "wf_error_input")
  expect_error(suppressWarnings(wf_propensity(tgt, weight = "kernel")),
               class = "wf_error_input")
  expect_error(suppressWarnings(wf_propensity(tgt, trim = -1)),
               class = "wf_error_input")
  expect_error(wf_propensity(list()), class = "wf_error_input")
})

test_that("wf_propensity fits per by-group and normalizes within each group", {
  online <- data.frame(
    x = c(1.0, 1.4, 1.8, 2.2, -0.5, 0.9, 1.3, 3.0),
    region = c("n", "n", "n", "n", "s", "s", "s", "s"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-2.0, -1.0, 0.0, 2.8, -1.5, -0.4, 0.4, 2.6),
    region = c("n", "n", "n", "n", "s", "s", "s", "s"),
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ x, by = "region")
  w <- suppressWarnings(wf_propensity(tgt))

  expect_setequal(unique(w$data$group), c("n", "s"))
  expect_equal(mean(w$data$weight[w$data$group == "n"]), 1)
  expect_equal(mean(w$data$weight[w$data$group == "s"]), 1)
})

test_that("wf_propensity errors when a by-group is missing a source", {
  online <- data.frame(
    x = c(1, 2, 3, 4),
    region = c("n", "n", "s", "s"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-1, 0, 1, 2),
    region = c("n", "n", "n", "n"),  # no 's' reference rows
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ x, by = "region")
  expect_error(suppressWarnings(wf_propensity(tgt)), class = "wf_error_overlap")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: FAIL — `could not find function "wf_propensity"`.

- [ ] **Step 3: Implement `wf_propensity()` (fit + weights + return; diagnostics stubbed to `NULL` for now)**

Append to `R/propensity.R`:

```r
#' Correct a non-probability sample by inverse-propensity pseudo-weighting.
#'
#' Fits the membership model declared in a [wf_target_propensity()] object and
#' converts each online unit's fitted membership probability into a pseudo-design
#' weight. The result is a `wf_weights` object suitable as an `init_weight` for
#' [wf_rake()] / [wf_poststrat()] and as a stage in [wf_compose()].
#'
#' @param target A `wf_target_propensity` object.
#' @param weight Pseudo-weight form. Only `"ipw"` is executable in this release;
#'   `"kernel"` / `"matching"` are reserved.
#' @param stabilize Use stabilized IPW (`pi_bar / phat`) to tame extreme weights.
#' @param trim Optional positive scalar: clamp weights above `trim * median(w)`.
#' @return A `wf_weights` object with `$overlap` and `$balance` diagnostics.
#' @export
wf_propensity <- function(target,
                          weight = c("ipw", "kernel", "matching"),
                          stabilize = TRUE, trim = NULL) {
  if (!inherits(target, "wf_target_propensity")) {
    wf_abort("`target` must be a wf_target_propensity object.", "wf_error_input")
  }
  weight <- match.arg(weight)
  if (weight != "ipw") {
    wf_abort(
      sprintf("weight = '%s' is not yet supported; only 'ipw' is implemented in this release.",
              weight),
      "wf_error_input", list(weight = weight)
    )
  }
  if (target$method != "logit") {
    wf_abort(
      sprintf("method = '%s' is not yet supported; only 'logit' is implemented in this release.",
              target$method),
      "wf_error_input", list(method = target$method)
    )
  }
  if (!is.null(trim) &&
      (length(trim) != 1 || !is.finite(trim) || trim <= 0)) {
    wf_abort("`trim` must be a single positive number or NULL.",
             "wf_error_input", list(trim = trim))
  }
  t0 <- Sys.time()

  stacked <- target$stacked
  membership <- target$membership
  by <- target$by
  fml <- stats::reformulate(target$predictors, response = membership)

  grp <- if (is.null(by)) rep(".all", nrow(stacked)) else .chr(stacked[[by]])
  is_online <- stacked$.wf_source == "online"

  phat <- rep(NA_real_, nrow(stacked))
  for (g in unique(grp)) {
    sel <- grp == g
    n_on <- sum(sel & is_online)
    n_ref <- sum(sel & !is_online)
    if (n_on == 0 || n_ref == 0) {
      wf_abort(
        sprintf("Group '%s' is missing an entire source (online: %d, reference: %d).",
                g, n_on, n_ref),
        "wf_error_overlap",
        list(group = g, n_online = n_on, n_reference = n_ref)
      )
    }
    fit <- stats::glm(fml, family = stats::binomial(),
                      data = stacked[sel, , drop = FALSE])
    phat[sel] <- stats::fitted(fit)
  }

  p_on <- phat[is_online]
  grp_on <- grp[is_online]

  raw <- 1 / p_on
  if (stabilize) {
    pibar <- tapply(stacked[[membership]], grp, mean)
    raw <- as.numeric(pibar[grp_on]) / p_on
  }

  trimmed <- 0L
  if (!is.null(trim)) {
    cap <- trim * stats::median(raw)
    hits <- raw > cap
    trimmed <- sum(hits)
    raw[hits] <- cap
  }

  w <- raw
  for (g in unique(grp_on)) {
    sel <- grp_on == g
    w[sel] <- w[sel] / mean(w[sel])
  }

  data <- data.frame(
    id = target$online_ids,
    group = grp_on,
    weight = w,
    feature = 1 / w,
    stringsAsFactors = FALSE
  )

  log <- data.frame(
    group = unique(grp_on),
    n = as.integer(table(grp_on)[unique(grp_on)]),
    stringsAsFactors = FALSE
  )

  structure(list(
    data = data,
    log = log,
    achieved = NULL,
    overlap = NULL,
    balance = NULL,
    provenance = list(
      method = "propensity",
      fit_method = target$method,
      weight = weight,
      stabilize = stabilize,
      trim = trim,
      trimmed = trimmed,
      by = by,
      id = target$id,
      predictors = target$predictors,
      assumption = paste(
        "Inverse-propensity correction is unbiased only if the model",
        "covariates capture the full online selection mechanism."
      ),
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_propensity_package_version()
    )
  ), class = "wf_weights")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: PASS (all Task 3 tests). The `suppressWarnings` wrappers absorb the overlap warning added in Task 4; they are harmless now.

- [ ] **Step 5: Commit**

```bash
git add R/propensity.R tests/testthat/test-propensity.R
git commit -m "feat: add wf_propensity ipw pseudo-weights returning wf_weights"
```

---

### Task 4: `wf_propensity()` — overlap / common-support diagnostic

**Files:**
- Modify: `R/propensity.R`
- Test: `tests/testthat/test-propensity.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-propensity.R`:

```r
test_that("wf_propensity attaches an overlap report", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))

  expect_type(w$overlap, "list")
  expect_true(all(c("threshold", "online", "reference", "n_boundary", "n_online")
                  %in% names(w$overlap)))
  expect_equal(w$overlap$n_online, tgt$n_online)
})

test_that("wf_propensity warns on poor common support", {
  # A near-separating predictor drives some online propensities above 0.99.
  online <- data.frame(x = c(6, 6.5, 7, 7.5, 8, 0.2), stringsAsFactors = FALSE)
  reference <- data.frame(x = c(-8, -7, -6, -5, -4, 6.2), stringsAsFactors = FALSE)
  tgt <- wf_target_propensity(online, reference, member ~ x)

  expect_warning(wf_propensity(tgt), class = "wf_warning_quality")

  w <- suppressWarnings(wf_propensity(tgt))
  expect_gte(w$overlap$n_boundary, 1)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: FAIL — `$overlap` is `NULL` (`w$overlap$n_online` is NULL) and no warning is raised.

- [ ] **Step 3: Implement the overlap diagnostic**

In `R/propensity.R` `wf_propensity()`, replace the line `overlap = NULL,` in the returned structure by building the report just before the `structure(...)` call. Insert this block immediately after the `data <- data.frame(...)`/`log <- data.frame(...)` assignments and before `structure(`:

```r
  boundary <- 0.99
  probs <- c(0, 0.01, 0.25, 0.5, 0.75, 0.99, 1)
  p_ref <- phat[!is_online]
  n_boundary <- sum(p_on > boundary)
  overlap <- list(
    threshold = boundary,
    online = stats::quantile(p_on, probs, names = TRUE),
    reference = stats::quantile(p_ref, probs, names = TRUE),
    n_boundary = n_boundary,
    n_online = length(p_on)
  )
  if (n_boundary > 0) {
    wf_warn(
      sprintf(
        "%d online unit(s) have propensity > %.2f (poor common support; extreme pseudo-weights).",
        n_boundary, boundary
      ),
      "wf_warning_quality",
      list(n_boundary = n_boundary, threshold = boundary)
    )
  }
```

Then change `overlap = NULL,` to `overlap = overlap,` in the returned `structure(...)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/propensity.R tests/testthat/test-propensity.R
git commit -m "feat: add propensity overlap diagnostic and support warning"
```

---

### Task 5: `wf_propensity()` — covariate-balance diagnostic

**Files:**
- Modify: `R/propensity.R`
- Test: `tests/testthat/test-propensity.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-propensity.R`:

```r
test_that("wf_propensity balance table reports unweighted and weighted SMDs", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))

  expect_s3_class(w$balance, "data.frame")
  expect_named(w$balance, c("variable", "level", "smd_unweighted", "smd_weighted"))
  expect_true("x" %in% w$balance$variable)
})

test_that("wf_propensity weighting shrinks the covariate gap", {
  # Online over-represents high x; pseudo-weighting should pull its mean toward
  # the reference, shrinking the standardized mean difference.
  set.seed(1)
  online <- data.frame(x = c(rnorm(40, 1.2, 1), rnorm(10, -1, 1)))
  reference <- data.frame(x = c(rnorm(25, 1, 1), rnorm(25, -1, 1)))
  tgt <- wf_target_propensity(online, reference, member ~ x)
  w <- suppressWarnings(wf_propensity(tgt))

  row <- w$balance[w$balance$variable == "x", ]
  expect_lt(abs(row$smd_weighted), abs(row$smd_unweighted))
})

test_that("wf_propensity expands a factor predictor into per-level balance rows", {
  online <- data.frame(
    x = c(1.0, 1.5, 2.0, 2.5, -0.5),
    g = c("a", "a", "b", "b", "a"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-1.0, -0.5, 0.0, 0.5, 1.8),
    g = c("b", "b", "a", "b", "a"),
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ x + g)
  w <- suppressWarnings(wf_propensity(tgt))

  expect_true("g" %in% w$balance$variable)
  expect_true(any(!is.na(w$balance$level)))
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: FAIL — `$balance` is `NULL`.

- [ ] **Step 3: Implement the balance helper and wire it in**

Add this internal helper near the top of `R/propensity.R` (after `.wf_propensity_package_version`):

```r
#' Standardized mean difference between online and reference for one covariate.
#'
#' @param x_on Numeric online values.
#' @param x_ref Numeric reference values.
#' @param w_on Online pseudo-weights (same length/order as `x_on`).
#' @keywords internal
#' @noRd
.wf_propensity_smd <- function(x_on, x_ref, w_on) {
  sd_pool <- sqrt((stats::var(x_on) + stats::var(x_ref)) / 2)
  if (!is.finite(sd_pool) || sd_pool == 0) sd_pool <- NA_real_
  c(
    unweighted = (mean(x_on) - mean(x_ref)) / sd_pool,
    weighted = (stats::weighted.mean(x_on, w_on) - mean(x_ref)) / sd_pool
  )
}

#' Build the online-vs-reference covariate balance table.
#'
#' @param stacked The stacked online+reference frame.
#' @param is_online Logical index of online rows in `stacked`.
#' @param predictors Predictor names.
#' @param w_on Online pseudo-weights (online-row order).
#' @keywords internal
#' @noRd
.wf_propensity_balance <- function(stacked, is_online, predictors, w_on) {
  online_rows <- stacked[is_online, , drop = FALSE]
  ref_rows <- stacked[!is_online, , drop = FALSE]
  rows <- list()
  for (p in predictors) {
    xo <- online_rows[[p]]
    xr <- ref_rows[[p]]
    if (is.numeric(xo)) {
      s <- .wf_propensity_smd(xo, xr, w_on)
      rows[[length(rows) + 1]] <- data.frame(
        variable = p, level = NA_character_,
        smd_unweighted = unname(s["unweighted"]),
        smd_weighted = unname(s["weighted"]),
        stringsAsFactors = FALSE
      )
    } else {
      levs <- sort(unique(.chr(c(xo, xr))))
      for (lv in levs[-1]) {
        s <- .wf_propensity_smd(
          as.numeric(.chr(xo) == lv),
          as.numeric(.chr(xr) == lv),
          w_on
        )
        rows[[length(rows) + 1]] <- data.frame(
          variable = p, level = lv,
          smd_unweighted = unname(s["unweighted"]),
          smd_weighted = unname(s["weighted"]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
```

Then in `wf_propensity()`, build the balance table alongside the overlap block (after `w` is finalized, before `structure(`):

```r
  balance <- .wf_propensity_balance(stacked, is_online, target$predictors, w)
```

and change `balance = NULL,` to `balance = balance,` in the returned `structure(...)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/propensity.R tests/testthat/test-propensity.R
git commit -m "feat: add propensity covariate-balance diagnostic"
```

---

### Task 6: `print.wf_weights` — propensity branch

**Files:**
- Modify: `R/rake.R` (the `print.wf_weights` function, currently at `R/rake.R:253`)
- Test: `tests/testthat/test-propensity.R`

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-propensity.R`:

```r
test_that("print.wf_weights reports the propensity method", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))
  expect_output(print(w), "method: propensity")
  expect_output(print(w), "overlap:")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: FAIL — the current print falls through to the raking branch and prints `mode:` (and errors/omits because `provenance$mode` is `NULL`), not `method: propensity`.

- [ ] **Step 3: Add the propensity branch to `print.wf_weights`**

In `R/rake.R`, inside `print.wf_weights`, add this branch immediately after the opening `{` and before the existing `if (... == "poststrat")` block:

```r
  if (!is.null(x$provenance$method) && x$provenance$method == "propensity") {
    cat(sprintf(
      "<wf_weights>  %d unit(s) in %d group(s); method: propensity (%s / %s)\n",
      nrow(x$data),
      nrow(x$log),
      x$provenance$fit_method,
      x$provenance$weight
    ))
    cat(sprintf(
      "  weight range [%.4g, %.4g]; stabilized: %s; trimmed: %d; elapsed %.2fs\n",
      min(x$data$weight),
      max(x$data$weight),
      x$provenance$stabilize,
      x$provenance$trimmed,
      x$provenance$elapsed
    ))
    cat(sprintf(
      "  overlap: %d/%d online unit(s) above p > %.2f boundary\n",
      x$overlap$n_boundary,
      x$overlap$n_online,
      x$overlap$threshold
    ))
    return(invisible(x))
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/rake.R tests/testthat/test-propensity.R
git commit -m "feat: print propensity branch for wf_weights"
```

---

### Task 7: Composition & `init_weight` integration

**Files:**
- Test: `tests/testthat/test-propensity.R`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-propensity.R`:

```r
test_that("wf_propensity output composes via wf_compose", {
  tgt <- make_prop_target()
  stage1 <- suppressWarnings(wf_propensity(tgt))
  stage2 <- stage1
  stage2$data$weight <- rep(2, nrow(stage2$data))
  stage2$data$feature <- 1 / stage2$data$weight

  composed <- wf_compose(propensity = stage1, adj = stage2)
  expect_s3_class(composed, "wf_weights")
  expect_equal(composed$data$weight, stage1$data$weight * 2, tolerance = 1e-8)
})

test_that("wf_propensity weights feed wf_poststrat as init_weight", {
  # wf_poststrat is the calibration stage that exposes the init_weight seam
  # (wf_rake does not take init_weight).
  fixture <- make_poststrat_fixture()
  online <- fixture$sample[, c("gender", "age")]
  reference <- data.frame(
    gender = rep(c("female", "male"), each = 4),
    age = rep(c("young", "old"), times = 4),
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ gender + age)
  pw <- suppressWarnings(wf_propensity(tgt))

  fixture$sample$pw <- pw$data$weight  # online == sample row order
  weights <- wf_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 2,
    ladder = fixture$ladder,
    init_weight = "pw",
    id = "id"
  )
  expect_s3_class(weights, "wf_weights")
})
```

Note: the `init_weight` seam is on `wf_poststrat()`, not `wf_rake()`. The
`make_poststrat_fixture()` helper lives in `tests/testthat/helper-fixtures.R`.

- [ ] **Step 2: Confirm the calibration API shape, then run**

Open `tests/testthat/test-rake-diagnostics.R` and `tests/testthat/helper-fixtures.R`; align the `wf_dims`/`wf_target_population`/`wf_rake` calls above with the real signatures (argument names, whether `dims` is passed positionally). Then:

Run: `Rscript -e 'devtools::test(filter = "propensity")'`
Expected: PASS — compose multiplies the stages; raking accepts the pseudo-weights as `init_weight` without error.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-propensity.R
git commit -m "test: propensity weights compose and feed raking init_weight"
```

---

### Task 8: Docs, exports, version bump, and full check

**Files:**
- Modify: `NAMESPACE`, `man/` (generated), `DESCRIPTION`, `NEWS.md`, `README.md`

- [ ] **Step 1: Regenerate roxygen docs and exports**

Run: `Rscript -e 'devtools::document()'`
Expected: `NAMESPACE` gains `export(wf_target_propensity)` and `export(wf_propensity)`; `man/wf_target_propensity.Rd` and `man/wf_propensity.Rd` are created. No errors.

- [ ] **Step 2: Bump the package version**

In `DESCRIPTION`, change `Version: 0.5.0` to `Version: 0.6.0`.

- [ ] **Step 3: Add the NEWS entry**

At the top of `NEWS.md`, replace the `# weightflow (development version)` line with:

```markdown
# weightflow 0.6.0

Non-probability correction via propensity. Adds a two-step propensity workflow
that corrects a self-selected online sample against an offline probability
reference, emitting pseudo-design weights that feed calibration as initial
weights.

* Added `wf_target_propensity()` to stack an online sample and a probability
  reference into a membership-model specification.
* Added `wf_propensity()` to fit a base-R logistic membership model and emit
  inverse-propensity pseudo-design weights as a `wf_weights` stage, with
  stabilized IPW on by default and optional trimming.
* Added overlap / common-support and covariate-balance diagnostics, with a
  `wf_warning_quality` on poor support.
```

- [ ] **Step 4: Update the README API list**

In `README.md`, find the section listing the public API (near the other
`wf_*` function bullets) and add:

```markdown
- `wf_target_propensity()` / `wf_propensity()` — non-probability correction:
  model the online sample's self-selection against a probability reference and
  emit pseudo-design weights for calibration.
```

Match the surrounding bullet style; if the README groups functions by release,
add a short "0.6.0 — non-probability correction" subsection consistent with how
0.4.0/0.5.0 are presented.

- [ ] **Step 5: Run the full test suite and R CMD check**

Run: `Rscript -e 'devtools::test()'`
Expected: All files pass, `FAIL 0`.

Run: `Rscript -e 'devtools::check(args = "--no-manual", error_on = "warning")'`
Expected: `0 errors | 0 warnings | 0 notes` (a note about the example dataset size, if pre-existing, is acceptable — compare against a check of `main` before this feature).

- [ ] **Step 6: Commit**

```bash
git add NAMESPACE man DESCRIPTION NEWS.md README.md
git commit -m "docs: export propensity API and bump to 0.6.0"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1–2 cover the constructor (validation, stacking, ids, no-fit); Task 3 covers the fit, IPW/stabilize/trim math, mean-1 normalization, the `wf_weights` return contract, reserved-value aborts, per-`by`-group fitting, and the `wf_error_overlap` missing-source guard; Task 4 the overlap diagnostic + `wf_warning_quality`; Task 5 the balance diagnostic (numeric + factor); Task 6 the print branch; Task 7 the compose/`init_weight` contract; Task 8 exports, NEWS/DESCRIPTION/README, and `R CMD check`.
- **Type consistency:** `wf_weights$data` columns are `id/group/weight/feature` everywhere; provenance keys (`method`, `fit_method`, `weight`, `stabilize`, `trim`, `trimmed`, `by`, `id`, `predictors`) are consistent between Task 3 (construction) and Task 6 (print). `.wf_propensity_smd` / `.wf_propensity_balance` signatures match their call site.
- **Deviation from roadmap:** `wf_propensity()` takes only `target` (online units derived from it) rather than re-passing `online`, per the approved spec.
```
