test_that("parallel worker resolution never exceeds the CRAN two-core limit", {
  old <- options(wfc.parallel.cores = 64L)
  on.exit(options(old), add = TRUE)

  expected <- if (identical(.Platform$OS.type, "windows")) 1L else 2L
  expect_equal(.wf_parallel_workers(100L, use_parallel = TRUE), expected)
})

test_that("wf_rake parallel execution matches serial output", {
  old <- options(wfc.parallel.cores = 2L)
  on.exit(options(old), add = TRUE)

  fixture <- make_weightflow_fixture()
  serial <- .wf_rake_engine(fixture$sample, fixture$target, id = "id", tol = 1e-10)
  forked <- .wf_rake_engine(
    fixture$sample,
    fixture$target,
    id = "id",
    tol = 1e-10,
    parallel = TRUE,
    progress = TRUE
  )

  serial_weight <- stats::setNames(serial$data$weight, serial$data$id)
  forked_weight <- stats::setNames(forked$data$weight, forked$data$id)

  expect_equal(forked_weight[names(serial_weight)], serial_weight, tolerance = 1e-10)
  expect_true(forked$provenance$parallel)
  expect_true(forked$provenance$progress)
  expect_gte(forked$provenance$parallel_workers, 1)
})

test_that("wf_poststrat records parallel and progress provenance", {
  old <- options(wfc.parallel.cores = 2L)
  on.exit(options(old), add = TRUE)

  fixture <- make_poststrat_fixture()
  weights <- .wf_poststrat_engine(
    fixture$sample,
    fixture$target,
    min_cell = 1,
    ladder = fixture$ladder,
    id = "id",
    parallel = TRUE,
    progress = TRUE
  )

  expect_s3_class(weights, "wf_weights")
  expect_true(weights$provenance$parallel)
  expect_true(weights$provenance$progress)
  expect_gte(weights$provenance$parallel_workers, 1)
})

test_that("wf_replicates parallel execution matches serial output", {
  old <- options(wfc.parallel.cores = 2L)
  on.exit(options(old), add = TRUE)

  d <- make_design_data()
  refit <- function(data, weights) {
    structure(list(
      data = data.frame(
        id = data$id,
        group = "all",
        weight = weights,
        feature = 1 / weights,
        stringsAsFactors = FALSE
      )
    ), class = "wf_weights")
  }
  serial <- wf_replicates(
    d,
    refit,
    method = "bootstrap",
    R = 12,
    strata = "stratum",
    clusters = "psu",
    id = "id",
    seed = 10
  )
  forked <- wf_replicates(
    d,
    refit,
    method = "bootstrap",
    R = 12,
    strata = "stratum",
    clusters = "psu",
    id = "id",
    seed = 10,
    parallel = TRUE
  )

  expect_equal(forked$base, serial$base)
  expect_equal(forked$replicates, serial$replicates)
  expect_true(forked$provenance$parallel)
  expect_gte(forked$provenance$parallel_workers, 1)
})

test_that(".wf_parallel_map replays classed warnings and errors", {
  old <- options(wfc.parallel.cores = 2L)
  on.exit(options(old), add = TRUE)

  expect_warning(
    .wf_parallel_map(
      as.list(1:2),
      function(i) {
        if (i == 2) {
          wf_warn("parallel warning", "wf_warning_data", list(i = i))
        }
        i
      },
      use_parallel = TRUE
    ),
    class = "wf_warning_data"
  )

  expect_error(
    .wf_parallel_map(
      as.list(1:2),
      function(i) {
        if (i == 2) {
          wf_abort("parallel error", "wf_error_input", list(i = i))
        }
        i
      },
      use_parallel = TRUE
    ),
    class = "wf_error_input"
  )
})
