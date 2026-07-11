test_that("wf_calibrate dispatches to raking", {
  fixture <- make_weightflow_fixture()

  direct <- wf_rake(fixture$sample, fixture$target, id = "id", tol = 1e-8)
  via <- wf_calibrate(fixture$sample, fixture$target, method = "raking", id = "id", tol = 1e-8)

  expect_s3_class(via, "wf_weights")
  expect_equal(via$data$weight, direct$data$weight, tolerance = 1e-8)
  expect_equal(via$provenance$method, "raking")
})

test_that("wf_calibrate defaults to raking", {
  fixture <- make_weightflow_fixture()

  via <- wf_calibrate(fixture$sample, fixture$target, id = "id", tol = 1e-8)

  expect_s3_class(via, "wf_weights")
  expect_equal(via$provenance$method, "raking")
})

test_that("wf_calibrate dispatches to poststrat", {
  fixture <- make_poststrat_fixture()

  direct <- wf_poststrat(fixture$sample, fixture$target, min_cell = 1, ladder = fixture$ladder, id = "id")
  via <- wf_calibrate(
    fixture$sample,
    fixture$target,
    method = "poststrat",
    min_cell = 1,
    ladder = fixture$ladder,
    id = "id"
  )

  expect_s3_class(via, "wf_weights")
  expect_equal(via$data$weight, direct$data$weight, tolerance = 1e-8)
  expect_equal(via$provenance$method, "poststrat")
})

test_that("wf_calibrate rejects unknown methods", {
  fixture <- make_weightflow_fixture()

  expect_error(
    wf_calibrate(fixture$sample, fixture$target, method = "linear"),
    class = "wf_error_input"
  )
})

test_that("foundation API exports are available", {
  expect_true(is.function(wf_target_manual))
  expect_true(is.function(wf_target_shrink))
  expect_true(is.function(wf_suggest_collapse))
  expect_true(is.function(wf_calibrate))
})
