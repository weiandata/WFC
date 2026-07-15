test_that("subjective target APIs are absent", {
  exports <- getNamespaceExports("WFC")

  expect_false("wf_target_manual" %in% exports)
  expect_false("wf_target_shrink" %in% exports)
})

test_that("inline moments are blocked before entropy calibration", {
  fixture <- make_safe_workflow_fixture()
  sample <- fixture$design$data
  sample$x <- seq_len(nrow(sample))

  err <- tryCatch(
    wf_calibrate(
      sample,
      fixture$target,
      method = "ebal",
      moments = c(x = 1)
    ),
    error = identity
  )

  expect_s3_class(err, "wf_error_safety")
  expect_identical(err$data$code, "inline_moments_unsupported")
  expect_identical(err$data$field, "moments")
  expect_identical(
    err$data$next_actions,
    "import_verified_external_margins"
  )
})
