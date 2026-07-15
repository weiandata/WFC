make_pipeline_spec <- function(validate = NULL, stages = NULL) {
  if (is.null(stages)) {
    stages <- list(
      calibrate = list(method = "raking", id = "id", tol = 1e-8)
    )
  }
  wf_pipeline(
    target = list(
      mode = "population",
      key_map = c(gender = "gender", age = "age"),
      count = "count",
      by = "province"
    ),
    stages = stages,
    validate = validate
  )
}

test_that("wf_pipeline declares a stable serializable spec", {
  spec <- make_pipeline_spec(validate = list(max_deff = 6))
  same <- make_pipeline_spec(validate = list(max_deff = 6))

  expect_s3_class(spec, "wf_pipeline")
  expect_true("wf_pipeline" %in% getNamespaceExports("WFC"))
  expect_true("wf_run" %in% getNamespaceExports("WFC"))
  expect_true("wf_validate" %in% getNamespaceExports("WFC"))
  expect_true("wf_audit_export" %in% getNamespaceExports("WFC"))
  expect_identical(spec$hash, same$hash)
  expect_identical(spec$target$mode, "population")
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
    wf_pipeline(
      list(mode = "population", key_map = c(gender = "gender"), count = "n"),
      list(clean = list())
    ),
    class = "wf_error_input"
  )
  expect_error(
    make_pipeline_spec(validate = list(max_deff = -1)),
    class = "wf_error_input"
  )
})

test_that("wf_run executes a population-target raking pipeline", {
  fixture <- make_weightflow_fixture()
  spec <- make_pipeline_spec()
  original_sample <- fixture$sample
  original_pop <- fixture$pop

  result <- wf_run(
    spec,
    fixture$sample,
    fixture$dims,
    population = fixture$pop
  )
  direct <- wf_rake(
    fixture$sample,
    fixture$target,
    id = "id",
    tol = 1e-8
  )
  direct$provenance$method <- "raking"

  expect_s3_class(result, "wf_weights")
  expect_identical(result$provenance$pipeline_hash, spec$hash)
  expect_identical(result$provenance$pipeline$target_mode, "population")
  expect_identical(result$provenance$pipeline$stages, "calibrate")
  expect_equal(
    result$data$weight[match(direct$data$id, result$data$id)],
    direct$data$weight,
    tolerance = 1e-8
  )
  expect_identical(fixture$sample, original_sample)
  expect_identical(fixture$pop, original_pop)
})

test_that("wf_run accepts numeric base weights for replicate refit closures", {
  fixture <- make_weightflow_fixture()
  spec <- make_pipeline_spec()
  base <- rep(1, nrow(fixture$sample))
  base[[1]] <- 3

  result <- wf_run(
    spec,
    fixture$sample,
    fixture$dims,
    population = fixture$pop,
    base_weight = base
  )

  direct_sample <- fixture$sample
  direct_sample$.base <- base
  direct <- wf_rake(
    direct_sample,
    fixture$target,
    id = "id",
    init_weight = ".base",
    tol = 1e-8
  )

  expect_equal(
    result$data$weight[match(direct$data$id, result$data$id)],
    direct$data$weight,
    tolerance = 1e-8
  )
  expect_identical(result$provenance$init_weight, ".wf_base_weight")
})

test_that("wf_run can prepend a propensity stage", {
  fixture <- make_weightflow_fixture()
  reference <- fixture$sample
  reference$id <- paste0("ref", seq_len(nrow(reference)))
  spec <- make_pipeline_spec(
    stages = list(
      propensity = list(
        formula = member ~ gender + age,
        by = "province",
        id = "id"
      ),
      calibrate = list(method = "raking", id = "id", tol = 1e-8)
    )
  )

  result <- suppressWarnings(wf_run(
    spec,
    fixture$sample,
    fixture$dims,
    population = fixture$pop,
    reference = reference
  ))

  expect_s3_class(result, "wf_weights")
  expect_identical(result$provenance$pipeline$stages, c("propensity", "calibrate"))
  expect_identical(
    result$provenance$pipeline_stages$propensity$method,
    "propensity"
  )
  expect_true(all(result$data$weight > 0))
})

test_that("pipeline validation records classed quality warnings", {
  fixture <- make_weightflow_fixture()
  spec <- make_pipeline_spec(validate = list(max_deff = 1))

  expect_warning(
    result <- wf_run(
      spec,
      fixture$sample,
      fixture$dims,
      population = fixture$pop
    ),
    class = "wf_warning_quality"
  )

  expect_s3_class(result$pipeline_validation, "wf_pipeline_validation")
  expect_false(result$pipeline_validation$ok)
  expect_true("max_deff" %in% result$pipeline_validation$issues$check)
})

test_that("wf_validate passes unchanged weights and detects drift", {
  fixture <- make_weightflow_fixture()
  weights <- wf_rake(
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
  expect_true(any(validation$issues$check %in% c("deff_delta", "unit_weight_ratio")))
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

test_that("wf_audit_export writes provenance and input hashes", {
  fixture <- make_weightflow_fixture()
  spec <- make_pipeline_spec()
  result <- wf_run(
    spec,
    fixture$sample,
    fixture$dims,
    population = fixture$pop
  )
  path <- tempfile(fileext = ".json")

  out <- wf_audit_export(
    result,
    path,
    inputs = list(sample = fixture$sample, population = fixture$pop),
    extra = list(release = "0.13.0")
  )
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")

  expect_identical(out, path)
  expect_true(file.exists(path))
  expect_match(text, "\"schema\":\"wfc_audit_v2\"", fixed = TRUE)
  expect_match(text, "\"pipeline_hash\"", fixed = TRUE)
  expect_match(text, "\"input_hashes\"", fixed = TRUE)
  expect_match(text, "\"release\":\"0.13.0\"", fixed = TRUE)

  expect_error(
    wf_audit_export(result, file.path(path, "missing", "audit.json")),
    class = "wf_error_input"
  )
})
