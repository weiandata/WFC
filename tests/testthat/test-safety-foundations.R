test_that("safety errors expose stable machine payloads", {
  err <- tryCatch(.wf_safety_abort(
    "target_period_missing", "Reference period is required.",
    field = "reference_period", next_actions = "supply_source_metadata"
  ), error = identity)

  expect_s3_class(err, "wf_error_safety")
  expect_identical(err$data$code, "target_period_missing")
  expect_identical(err$data$severity, "blocking")
  expect_identical(err$data$next_actions, "supply_source_metadata")
})

test_that("identities are stable SHA-256 strings", {
  p <- tempfile()
  writeLines("x", p)

  expect_match(.wf_sha256_file(p), "^[0-9a-f]{64}$")
  expect_identical(
    .wf_sha256_object(list(a = 1)),
    .wf_sha256_object(list(a = 1))
  )
})
