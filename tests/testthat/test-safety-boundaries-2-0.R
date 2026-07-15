expect_safety_code <- function(object, code) {
  expect_s3_class(object, "wf_error_safety")
  expect_identical(object$data$code, code)
}

test_that("raw samples and arbitrary targets do not reach weighting engines", {
  fixture <- make_safe_workflow_fixture()
  raw <- fixture$design$data

  expect_safety_code(tryCatch(
    wf_calibrate(raw, fixture$target, method = "raking"),
    error = identity
  ), "verified_weighting_inputs_required")
  expect_safety_code(tryCatch(
    wf_rake(raw, fixture$target),
    error = identity
  ), "verified_weighting_inputs_required")
  expect_safety_code(tryCatch(
    wf_autoweigh(raw, fixture$target, fixture$dims, interactive = FALSE),
    error = identity
  ), "verified_weighting_inputs_required")
  expect_safety_code(tryCatch(
    wf_auto_trim(raw, fixture$target, caps = c(2, 4)),
    error = identity
  ), "verified_weighting_inputs_required")
  expect_error(
    wf_plan_weights(fixture$design, unclass(fixture$target), fixture$dims),
    class = "wf_error_safety"
  )
})

test_that("verified design and target objects reach supported public methods", {
  fixture <- make_safe_workflow_fixture()

  calibrated <- wf_calibrate(
    fixture$design,
    fixture$target,
    method = "raking"
  )
  raked <- wf_rake(fixture$design, fixture$target)
  guided <- wf_autoweigh(
    fixture$design,
    fixture$target,
    fixture$dims,
    method = "raking",
    trim = NULL,
    interactive = FALSE
  )
  trim_review <- wf_auto_trim(
    fixture$design,
    fixture$target,
    caps = c(2, 4),
    max_deff = 20
  )

  expect_s3_class(calibrated, "wf_weights")
  expect_s3_class(raked, "wf_weights")
  expect_s3_class(guided, "wf_autoweigh_result")
  expect_s3_class(trim_review, "wf_auto_trim")
  expect_identical(calibrated$provenance$design_identity, fixture$design$identity)
  expect_identical(calibrated$provenance$target_identity, fixture$target$identity)
})

test_that("manual pipelines and unverified object targets are blocked", {
  manual <- tryCatch(
    wf_pipeline(
      list(mode = "manual"),
      list(calibrate = list(method = "raking"))
    ),
    error = identity
  )
  expect_safety_code(manual, "manual_pipeline_unsupported")

  ordinary_target <- make_weightflow_fixture()$target
  object_mode <- tryCatch(
    wf_pipeline(
      ordinary_target,
      list(calibrate = list(method = "raking"))
    ),
    error = identity
  )
  expect_safety_code(object_mode, "verified_target_required")

  expect_false("margins" %in% names(formals(wf_run)))
})
