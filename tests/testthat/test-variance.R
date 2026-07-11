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

test_that("wf_replicates + wf_variance run through a real raking refit", {
  fixture <- make_weightflow_fixture()
  d <- fixture$sample
  d$y <- as.numeric(d$age == "young")

  refit <- function(data, weights) {
    data$.bw <- weights
    wf_rake(data, fixture$target, id = "id", init_weight = ".bw",
            precheck = FALSE)
  }

  # Delete-one jackknife on this small fixture: every marginal category keeps
  # >= 3 units per replicate, so each re-raking stays feasible. (A bootstrap on
  # a fixture this sparse can empty a calibration cell and is infeasible by
  # design.)
  rep_w <- wf_replicates(d, refit, method = "jackknife", id = "id")
  out <- wf_variance(rep_w, function(w, data) sum(w * data$y) / sum(w), d)

  expect_s3_class(out, "wf_variance_result")
  expect_true(is.finite(out$table$se))
  expect_true(out$table$se >= 0)
  expect_true(out$table$ci_lower <= out$table$estimate)
})
