make_interoperability_weights <- function() {
  fixture <- make_weightflow_fixture()
  weights <- wf_rake(
    fixture$sample,
    fixture$target,
    id = "id",
    tol = 1e-8
  )
  list(fixture = fixture, weights = weights)
}

test_that("dependency checks raise a classed error", {
  expect_error(
    .wf_require_namespace(
      "wfc_package_that_does_not_exist",
      "test interoperability"
    ),
    class = "wf_error_dependency"
  )
})

test_that("as_svydesign is exported", {
  expect_true("as_svydesign" %in% getNamespaceExports("WFC"))
  expect_true(is.function(as_svydesign))
})

test_that("as_svydesign aligns weights by ID and preserves input order", {
  testthat::skip_if_not_installed("survey")
  setup <- make_interoperability_weights()
  data <- setup$fixture$sample[rev(seq_len(nrow(setup$fixture$sample))), ]
  data$outcome <- as.numeric(data$age == "young")
  original_data <- data
  original_weights <- setup$weights

  design <- as_svydesign(setup$weights, data, id = "id")
  aligned <- setup$weights$data$weight[
    match(data$id, setup$weights$data$id)
  ]

  expect_s3_class(design, "survey.design2")
  expect_equal(as.numeric(stats::weights(design)), aligned)
  expect_equal(design$variables$.wf_weight, aligned)
  expect_identical(design$variables$id, data$id)
  expect_identical(attr(design, "wfc_provenance"), setup$weights$provenance)
  expect_identical(data, original_data)
  expect_identical(setup$weights, original_weights)

  estimate <- survey::svymean(~outcome, design)
  expected <- sum(aligned * data$outcome) / sum(aligned)
  expect_equal(as.numeric(estimate), expected, tolerance = 1e-12)
})

test_that("as_svydesign forwards cluster, strata, and nesting controls", {
  testthat::skip_if_not_installed("survey")
  setup <- make_interoperability_weights()
  data <- setup$fixture$sample
  data$psu <- paste0(data$province, "_", seq_len(nrow(data)))

  design <- as_svydesign(
    setup$weights,
    data,
    id = "id",
    ids = ~psu,
    strata = ~province,
    nest = TRUE
  )

  expect_s3_class(design, "survey.design2")
  expect_equal(nrow(design$cluster), nrow(data))
  expect_equal(nrow(design$strata), nrow(data))
  expect_true(isTRUE(design$has.strata))
})

test_that("as_svydesign enforces exact unique IDs and reserved columns", {
  testthat::skip_if_not_installed("survey")
  setup <- make_interoperability_weights()
  data <- setup$fixture$sample

  expect_error(as_svydesign(list(), data), class = "wf_error_input")
  expect_error(
    as_svydesign(setup$weights, list()),
    class = "wf_error_input"
  )
  expect_error(
    as_svydesign(setup$weights, data, id = "missing"),
    class = "wf_error_schema"
  )

  duplicate_data <- data
  duplicate_data$id[[2]] <- duplicate_data$id[[1]]
  expect_error(
    as_svydesign(setup$weights, duplicate_data),
    class = "wf_error_schema"
  )

  duplicate_weights <- setup$weights
  duplicate_weights$data$id[[2]] <- duplicate_weights$data$id[[1]]
  expect_error(
    as_svydesign(duplicate_weights, data),
    class = "wf_error_schema"
  )

  expect_error(
    as_svydesign(setup$weights, data[-1, ]),
    class = "wf_error_schema"
  )

  extra_data <- rbind(data, data[1, ])
  extra_data$id[nrow(extra_data)] <- "extra-id"
  expect_error(
    as_svydesign(setup$weights, extra_data),
    class = "wf_error_schema"
  )

  collision <- data
  collision$.wf_weight <- 1
  expect_error(
    as_svydesign(setup$weights, collision),
    class = "wf_error_schema"
  )

  expect_error(
    as_svydesign(setup$weights, data, weights = ~id),
    class = "wf_error_input"
  )
  expect_error(
    as_svydesign(setup$weights, data, probs = ~id),
    class = "wf_error_input"
  )
})
