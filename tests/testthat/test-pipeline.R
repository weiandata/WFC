make_pipeline_spec <- function(target, validate = NULL, stages = NULL) {
  if (is.null(stages)) {
    stages <- list(calibrate = list(method = "raking", tol = 1e-8))
  }
  wf_pipeline(target = target, stages = stages, validate = validate)
}

test_that("wf_pipeline declares a stable verified-target spec", {
  fixture <- make_safe_workflow_fixture()
  spec <- make_pipeline_spec(
    fixture$target,
    validate = list(max_deff = 6)
  )
  same <- make_pipeline_spec(
    fixture$target,
    validate = list(max_deff = 6)
  )

  expect_s3_class(spec, "wf_pipeline")
  expect_true("wf_pipeline" %in% getNamespaceExports("WFC"))
  expect_true("wf_run" %in% getNamespaceExports("WFC"))
  expect_true("wf_validate" %in% getNamespaceExports("WFC"))
  expect_true("wf_audit_export" %in% getNamespaceExports("WFC"))
  expect_identical(spec$hash, same$hash)
  expect_identical(spec$target$mode, "object")
  expect_identical(names(spec$stages), "calibrate")
  expect_output(print(spec), spec$hash, fixed = TRUE)

  expect_error(
    wf_pipeline(
      list(mode = "unknown"),
      list(calibrate = list(method = "raking"))
    ),
    class = "wf_error_input"
  )
  expect_error(
    wf_pipeline(fixture$target, list(clean = list())),
    class = "wf_error_input"
  )
  expect_error(
    make_pipeline_spec(fixture$target, validate = list(max_deff = -1)),
    class = "wf_error_input"
  )
})

test_that("wf_run executes verified object and population modes", {
  fixture <- make_safe_workflow_fixture()
  object_spec <- make_pipeline_spec(fixture$target)
  population_spec <- wf_pipeline(
    target = list(mode = "population"),
    stages = list(calibrate = list(method = "raking", tol = 1e-8))
  )

  object_result <- wf_run(object_spec, fixture$design, fixture$dims)
  population_result <- wf_run(
    population_spec,
    fixture$design,
    fixture$dims,
    population = fixture$target
  )
  direct <- .wf_rake_engine(
    fixture$design$data,
    fixture$target,
    id = fixture$design$roles$id,
    init_weight = fixture$design$roles$base_weight,
    tol = 1e-8
  )

  expect_s3_class(object_result, "wf_weights")
  expect_identical(object_result$provenance$pipeline_hash, object_spec$hash)
  expect_identical(object_result$provenance$pipeline$target_mode, "object")
  expect_equal(
    object_result$data$weight[match(direct$data$id, object_result$data$id)],
    direct$data$weight,
    tolerance = 1e-8
  )
  expect_equal(population_result$data$weight, object_result$data$weight)
})

test_that("wf_run owns design roles and blocks runtime propensity", {
  fixture <- make_safe_workflow_fixture()
  spec <- make_pipeline_spec(fixture$target)

  expect_error(
    wf_run(spec, fixture$design, base_weight = rep(1, nrow(fixture$design$data))),
    class = "wf_error_safety"
  )

  propensity_spec <- make_pipeline_spec(
    fixture$target,
    stages = list(
      propensity = list(formula = member ~ gender + age),
      calibrate = list(method = "raking")
    )
  )
  err <- tryCatch(
    wf_run(propensity_spec, fixture$design),
    error = identity
  )
  expect_s3_class(err, "wf_error_safety")
  expect_identical(err$data$code, "pipeline_propensity_unsupported")
})

test_that("pipeline validation records classed quality warnings", {
  fixture <- make_safe_workflow_fixture()
  spec <- make_pipeline_spec(
    fixture$target,
    validate = list(max_deff = 1)
  )

  expect_warning(
    result <- wf_run(spec, fixture$design, fixture$dims),
    class = "wf_warning_quality"
  )

  expect_s3_class(result$pipeline_validation, "wf_pipeline_validation")
  expect_false(result$pipeline_validation$ok)
  expect_true("max_deff" %in% result$pipeline_validation$issues$check)
})

test_that("wf_validate passes unchanged weights and detects drift", {
  fixture <- make_weightflow_fixture()
  weights <- .wf_rake_engine(
    fixture$sample,
    fixture$target,
    id = "id",
    tol = 1e-8
  )
  weights$provenance$method <- "raking"

  clean <- wf_validate(weights, weights, fixture$target, on_issue = "none")
  expect_s3_class(clean, "wf_validation")
  expect_true(clean$ok)
  expect_equal(nrow(clean$issues), 0)
  expect_equal(nrow(clean$comparison), 2)
  expect_output(print(clean), "PASS", fixed = TRUE)

  drifted <- weights
  drifted$data$weight[[1]] <- drifted$data$weight[[1]] * 20
  expect_warning(
    validation <- wf_validate(
      drifted,
      weights,
      fixture$target,
      max_deff_delta = 0.01,
      max_ratio_p99 = 1.05
    ),
    class = "wf_warning_quality"
  )
  expect_false(validation$ok)
  expect_true(any(validation$issues$check %in% c(
    "deff_delta",
    "unit_weight_ratio"
  )))
  expect_output(print(validation), "DRIFT DETECTED", fixed = TRUE)

  expect_error(
    wf_validate(
      drifted,
      weights,
      fixture$target,
      max_deff_delta = 0.01,
      on_issue = "error"
    ),
    class = "wf_error_input"
  )
})

test_that("wf_audit_export writes verified pipeline provenance", {
  fixture <- make_safe_workflow_fixture()
  spec <- make_pipeline_spec(fixture$target)
  result <- wf_run(spec, fixture$design, fixture$dims)
  path <- tempfile(fileext = ".json")

  out <- wf_audit_export(
    result,
    path,
    inputs = list(design = fixture$design, target = fixture$target),
    extra = list(release = "2.0.0")
  )
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")

  expect_identical(out, path)
  expect_true(file.exists(path))
  expect_match(text, "\"schema\":\"wfc_audit_v2\"", fixed = TRUE)
  expect_match(text, "\"pipeline_hash\"", fixed = TRUE)
  expect_match(text, "\"input_hashes\"", fixed = TRUE)
  expect_match(text, "\"release\":\"2.0.0\"", fixed = TRUE)

  expect_error(
    wf_audit_export(result, file.path(path, "missing", "audit.json")),
    class = "wf_error_input"
  )
})
