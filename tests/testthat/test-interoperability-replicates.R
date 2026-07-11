interoperability_refit <- function(data, weights) {
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

interoperability_mean <- function(weights, data) {
  sum(weights * data$y) / sum(weights)
}

make_interoperability_replicates <- function(method, strata = "stratum") {
  data <- make_design_data()
  replicates <- suppressWarnings(wf_replicates(
    data,
    interoperability_refit,
    method = method,
    R = 40,
    strata = strata,
    clusters = "psu",
    id = "id",
    seed = 11
  ))
  list(data = data, replicates = replicates)
}

test_that("as_svrepdesign is exported", {
  expect_true("as_svrepdesign" %in% getNamespaceExports("WFC"))
  expect_true(is.function(as_svrepdesign))
})

test_that("as_svrepdesign maps WFC replication methods and stored scales", {
  testthat::skip_if_not_installed("survey")
  cases <- list(
    list(method = "bootstrap", strata = "stratum", type = "bootstrap"),
    list(method = "jackknife", strata = NULL, type = "JK1"),
    list(method = "jackknife", strata = "stratum", type = "JKn"),
    list(method = "brr", strata = "stratum", type = "BRR")
  )

  for (case in cases) {
    setup <- make_interoperability_replicates(case$method, case$strata)
    data <- setup$data[rev(seq_len(nrow(setup$data))), ]
    original <- setup$replicates
    design <- as_svrepdesign(setup$replicates, data, id = "id")
    order <- match(data$id, setup$replicates$base$id)

    expect_s3_class(design, "svyrep.design")
    expect_identical(design$type, case$type)
    expect_equal(design$scale, setup$replicates$scale)
    expect_equal(design$rscales, setup$replicates$rscales)
    expect_true(isTRUE(design$mse))
    expect_equal(
      as.numeric(stats::weights(design, type = "sampling")),
      setup$replicates$base$weight[order]
    )
    expect_equal(
      unname(stats::weights(design, type = "replication")),
      unname(setup$replicates$replicates[order, , drop = FALSE])
    )
    expect_equal(
      design$variables$.wf_weight,
      setup$replicates$base$weight[order]
    )
    expect_identical(
      attr(design, "wfc_provenance"),
      setup$replicates$provenance
    )
    expect_identical(setup$replicates, original)
  }
})

test_that("survey replicate estimates reproduce wf_variance", {
  testthat::skip_if_not_installed("survey")

  for (method in c("bootstrap", "jackknife", "brr")) {
    setup <- make_interoperability_replicates(method)
    data <- setup$data[rev(seq_len(nrow(setup$data))), ]
    design <- as_svrepdesign(setup$replicates, data, id = "id")
    survey_result <- survey::svymean(~y, design)
    wfc_result <- wf_variance(
      setup$replicates,
      interoperability_mean,
      setup$data
    )

    expect_equal(
      as.numeric(survey_result),
      wfc_result$table$estimate,
      tolerance = 1e-12
    )
    expect_equal(
      as.numeric(survey::SE(survey_result)),
      wfc_result$table$se,
      tolerance = 1e-12
    )
  }
})

test_that("as_svrepdesign forwards explicit degrees of freedom", {
  testthat::skip_if_not_installed("survey")
  setup <- make_interoperability_replicates("bootstrap")

  design <- as_svrepdesign(
    setup$replicates,
    setup$data,
    id = "id",
    degf = 3
  )

  expect_equal(as.numeric(survey::degf(design)), 3)
})

test_that("as_svrepdesign validates IDs, metadata, and reserved controls", {
  testthat::skip_if_not_installed("survey")
  setup <- make_interoperability_replicates("bootstrap")
  data <- setup$data

  expect_error(as_svrepdesign(list(), data), class = "wf_error_input")
  expect_error(
    as_svrepdesign(setup$replicates, list()),
    class = "wf_error_input"
  )
  expect_error(
    as_svrepdesign(setup$replicates, data[-1, ]),
    class = "wf_error_schema"
  )

  duplicate <- setup$replicates
  duplicate$base$id[[2]] <- duplicate$base$id[[1]]
  expect_error(
    as_svrepdesign(duplicate, data),
    class = "wf_error_schema"
  )

  collision <- data
  collision$.wf_weight <- 1
  expect_error(
    as_svrepdesign(setup$replicates, collision),
    class = "wf_error_schema"
  )

  malformed <- setup$replicates
  malformed$replicates <- malformed$replicates[-1, , drop = FALSE]
  expect_error(
    as_svrepdesign(malformed, data),
    class = "wf_error_internal"
  )

  malformed_method <- setup$replicates
  malformed_method$method <- "unknown"
  expect_error(
    as_svrepdesign(malformed_method, data),
    class = "wf_error_internal"
  )

  for (argument in c(
    "variables", "repweights", "weights", "type", "scale", "rscales",
    "combined.weights", "mse", "rho"
  )) {
    args <- list(r = setup$replicates, data = data)
    args[[argument]] <- 1
    expect_error(
      do.call(as_svrepdesign, args),
      class = "wf_error_input"
    )
  }
})
