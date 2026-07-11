test_that("wfc_example contains only simulated package data", {
  data("wfc_example", package = "WFC", envir = environment())

  expect_true(exists("wfc_example"))
  expect_true(is.list(wfc_example))
  expect_true(all(c("sample", "population", "dims") %in% names(wfc_example)))
  expect_true(is.data.frame(wfc_example$sample))
  expect_true(is.data.frame(wfc_example$population))
  expect_s3_class(wfc_example$dims, "wf_dims")
  expect_false(any(grepl("source", names(wfc_example))))
})

test_that("wfc_example supports the documented raking quick start", {
  data("wfc_example", package = "WFC", envir = environment())

  target <- wf_target_population(
    wfc_example$population,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = wfc_example$dims,
    by = "province"
  )

  check <- wf_precheck(wfc_example$sample, target, id = "id")
  expect_true(check$ok)

  weights <- wf_rake(wfc_example$sample, target, id = "id")
  expect_true(all(weights$log$converged))
  expect_true(all(weights$data$weight > 0))
})
