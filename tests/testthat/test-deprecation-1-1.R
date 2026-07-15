make_deprecated_manual_fixture <- function() {
  dims <- wf_dims(gender = c("female", "male"))
  margins <- data.frame(
    dimension = c("gender", "gender"),
    category = c("female", "male"),
    value = c(55, 45),
    stringsAsFactors = FALSE
  )
  list(dims = dims, margins = margins)
}

test_that("manual targets warn on every call with migration payload", {
  f <- make_deprecated_manual_fixture()
  captured <- NULL

  target <- withCallingHandlers(
    wf_target_manual(f$margins, f$dims),
    wf_warning_deprecated = function(warning) {
      captured <<- warning
      invokeRestart("muffleWarning")
    }
  )

  expect_s3_class(target, "wf_target")
  expect_identical(captured$data$removal, "2.0.0")
  expect_identical(captured$data$risk_code, "subjective_manual_target")
  expect_warning(
    wf_target_manual(f$margins, f$dims),
    class = "wf_warning_deprecated"
  )
})

test_that("target shrinkage warns without changing its calculation", {
  f <- make_deprecated_manual_fixture()
  local <- suppressWarnings(wf_target_manual(f$margins, f$dims))
  reference_margins <- f$margins
  reference_margins$value <- c(50, 50)
  reference <- suppressWarnings(
    wf_target_manual(reference_margins, f$dims)
  )

  expect_warning(
    shrunk <- wf_target_shrink(local, reference, 0.5),
    class = "wf_warning_deprecated"
  )

  expect_equal(
    unname(shrunk$groups$`_all_`$margins$gender),
    c(52.5, 47.5)
  )
})

test_that("inline entropy moments warn without changing numeric results", {
  dims <- wf_dims(gender = c("female", "male"))
  sample <- data.frame(
    id = paste0("r", 1:4),
    gender = c("female", "female", "male", "male"),
    x = c(0, 0.5, 1, 1.5),
    stringsAsFactors = FALSE
  )
  target <- wf_target_population(
    data.frame(gender = c("female", "male"), count = c(2, 2)),
    c(gender = "gender"),
    "count",
    dims
  )

  baseline <- suppressWarnings(wf_calibrate(
    sample,
    target,
    method = "ebal",
    id = "id",
    moments = c(x = 0.75)
  ))
  expect_warning(
    warned <- wf_calibrate(
      sample,
      target,
      method = "ebal",
      id = "id",
      moments = c(x = 0.75)
    ),
    class = "wf_warning_deprecated"
  )

  expect_equal(warned$data$weight, baseline$data$weight)
})

test_that("manual pipeline declarations and runtime margins both warn", {
  f <- make_deprecated_manual_fixture()
  sample <- data.frame(
    id = paste0("r", 1:4),
    gender = c("female", "female", "male", "male"),
    stringsAsFactors = FALSE
  )

  expect_warning(
    embedded <- wf_pipeline(
      target = list(mode = "manual", margins = f$margins),
      stages = list(calibrate = list(method = "raking", id = "id"))
    ),
    class = "wf_warning_deprecated"
  )
  expect_s3_class(embedded, "wf_pipeline")

  runtime <- suppressWarnings(wf_pipeline(
    target = list(mode = "manual"),
    stages = list(calibrate = list(method = "raking", id = "id"))
  ))
  risk_codes <- character()
  result <- withCallingHandlers(
    wf_run(runtime, sample, dims = f$dims, margins = f$margins),
    wf_warning_deprecated = function(warning) {
      risk_codes <<- c(risk_codes, warning$data$risk_code)
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(result, "wf_weights")
  expect_true("subjective_runtime_margins" %in% risk_codes)
})
