make_tidier_weights <- function() {
  fixture <- make_weightflow_fixture()
  weights <- wf_rake(
    fixture$sample,
    fixture$target,
    id = "id",
    tol = 1e-8
  )
  list(
    fixture = fixture,
    weights = weights,
    diagnostics = wf_diagnose(weights, fixture$target)
  )
}

make_tidier_blend_weights <- function(source, outcome) {
  structure(
    list(
      data = data.frame(
        id = paste0(source, "_", 1:4),
        group = "A",
        cell = rep(c("urban", "rural"), each = 2),
        weight = c(1, 2, 1, 2),
        outcome = outcome,
        stringsAsFactors = FALSE
      ),
      log = data.frame(group = "A", n = 4),
      achieved = NULL,
      provenance = list(method = source)
    ),
    class = "wf_weights"
  )
}

make_tidier_blend <- function(outcome = TRUE) {
  online <- make_tidier_blend_weights("online", c(1, 0, 1, 1))
  offline <- make_tidier_blend_weights("offline", c(0, 0, 1, 0))
  wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = if (outcome) "outcome" else NULL,
    lambda = "fixed",
    lambda_fixed = 0.5,
    sensitivity = FALSE
  )
}

tidier_refit <- function(data, weights) {
  structure(
    list(
      data = data.frame(
        id = data$id,
        group = "all",
        weight = weights,
        feature = 1 / weights,
        stringsAsFactors = FALSE
      )
    ),
    class = "wf_weights"
  )
}

make_tidier_variance <- function() {
  data <- make_design_data()
  replicates <- wf_replicates(
    data,
    tidier_refit,
    method = "bootstrap",
    R = 20,
    strata = "stratum",
    clusters = "psu",
    id = "id",
    seed = 4
  )
  wf_variance(
    replicates,
    function(weights, data) sum(weights * data$y) / sum(weights),
    data
  )
}

test_that("generics dispatches tidy methods for WFC result classes", {
  testthat::skip_if_not_installed("generics")
  setup <- make_tidier_weights()
  blend <- make_tidier_blend()
  variance <- make_tidier_variance()

  expect_identical(generics::tidy(setup$weights), setup$weights$data)
  expect_identical(
    generics::tidy(setup$diagnostics),
    setup$diagnostics$table
  )
  expect_identical(generics::tidy(blend), blend$estimates)
  expect_identical(generics::tidy(variance), variance$table)

  cell_blend <- make_tidier_blend(outcome = FALSE)
  expect_identical(generics::tidy(cell_blend), cell_blend$cell_weights)
})

test_that("glance.wf_weights returns an overall weighting summary", {
  testthat::skip_if_not_installed("generics")
  setup <- make_tidier_weights()
  glance <- generics::glance(setup$weights)
  weight <- setup$weights$data$weight

  expect_s3_class(glance, "data.frame")
  expect_equal(nrow(glance), 1)
  expect_identical(
    names(glance),
    c("n", "groups", "total_weight", "ess", "deff", "method")
  )
  expect_equal(glance$n, nrow(setup$weights$data))
  expect_equal(glance$groups, length(unique(setup$weights$data$group)))
  expect_equal(glance$total_weight, sum(weight))
  expect_equal(glance$ess, sum(weight)^2 / sum(weight^2))
  expect_equal(glance$deff, 1 + (stats::sd(weight) / mean(weight))^2)
  expect_identical(glance$method, "raking")
})

test_that("diagnostic, blend, and variance glance methods are stable", {
  testthat::skip_if_not_installed("generics")
  setup <- make_tidier_weights()
  blend <- make_tidier_blend()
  variance <- make_tidier_variance()

  diagnostic_glance <- generics::glance(setup$diagnostics)
  expect_identical(
    names(diagnostic_glance),
    c(
      "groups", "ok", "caveat", "failed", "worst_deff", "minimum_ess"
    )
  )
  expect_equal(diagnostic_glance$groups, nrow(setup$diagnostics$table))
  expect_equal(
    diagnostic_glance$worst_deff,
    max(setup$diagnostics$table$deff)
  )

  blend_glance <- generics::glance(blend)
  expect_identical(
    names(blend_glance),
    c(
      "cells", "groups", "lambda_min", "lambda_mean", "lambda_max",
      "trimmed_lambda_count", "one_source_cell_count"
    )
  )
  expect_equal(blend_glance$cells, nrow(blend$lambda))
  expect_equal(blend_glance$lambda_mean, mean(blend$lambda$lambda))

  variance_glance <- generics::glance(variance)
  expect_identical(
    names(variance_glance),
    c("method", "replicates", "level", "ci", "quantities", "maximum_se")
  )
  expect_equal(variance_glance$replicates, variance$provenance$R)
  expect_equal(variance_glance$maximum_se, max(variance$table$se))
})

test_that("augment.wf_weights joins by ID without mutating inputs", {
  testthat::skip_if_not_installed("generics")
  setup <- make_tidier_weights()
  data <- setup$fixture$sample[rev(seq_len(nrow(setup$fixture$sample))), ]
  original_data <- data
  original_weights <- setup$weights

  augmented <- generics::augment(setup$weights, data = data, id = "id")
  order <- match(data$id, setup$weights$data$id)

  expect_identical(
    names(augmented),
    c(names(data), ".weight", ".feature")
  )
  expect_equal(augmented$.weight, setup$weights$data$weight[order])
  expect_equal(augmented$.feature, setup$weights$data$feature[order])
  expect_identical(augmented$id, data$id)
  expect_identical(data, original_data)
  expect_identical(setup$weights, original_weights)
})

test_that("augment.wf_weights enforces exact IDs and output columns", {
  testthat::skip_if_not_installed("generics")
  setup <- make_tidier_weights()
  data <- setup$fixture$sample

  expect_error(
    generics::augment(setup$weights, data = list()),
    class = "wf_error_input"
  )
  expect_error(
    generics::augment(setup$weights, data = data, id = "missing"),
    class = "wf_error_schema"
  )
  expect_error(
    generics::augment(setup$weights, data = data[-1, ]),
    class = "wf_error_schema"
  )

  duplicate <- data
  duplicate$id[[2]] <- duplicate$id[[1]]
  expect_error(
    generics::augment(setup$weights, data = duplicate),
    class = "wf_error_schema"
  )

  collision <- data
  collision$.weight <- 1
  expect_error(
    generics::augment(setup$weights, data = collision),
    class = "wf_error_schema"
  )
  collision <- data
  collision$.feature <- 1
  expect_error(
    generics::augment(setup$weights, data = collision),
    class = "wf_error_schema"
  )
})
