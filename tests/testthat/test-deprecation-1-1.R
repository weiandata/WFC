test_that("the 1.1 contract preserves the completed deprecation record", {
  freeze <- system.file("stability/api-freeze.md", package = "WFC")
  expect_true(nzchar(freeze))
  contract <- readLines(freeze, warn = FALSE)

  expect_true(any(grepl("scheduled for removal in 2.0.0", contract, fixed = TRUE)))
  expect_true(any(grepl("manual target margins", contract, fixed = TRUE)))
  expect_true(any(grepl("target shrinkage", contract, fixed = TRUE)))
  expect_true(any(grepl("inline entropy-balancing moment targets", contract, fixed = TRUE)))
})

test_that("WFC 2.0 enforces rather than repeats 1.1 warnings", {
  exports <- getNamespaceExports("WFC")

  expect_false("wf_target_manual" %in% exports)
  expect_false("wf_target_shrink" %in% exports)

  fixture <- make_safe_workflow_fixture()
  err <- tryCatch(
    wf_calibrate(
      fixture$design$data,
      fixture$target,
      method = "ebal",
      moments = c(outcome = 0.5)
    ),
    error = identity
  )
  expect_s3_class(err, "wf_error_safety")
  expect_identical(err$data$code, "inline_moments_unsupported")
})
