run_autoweigh <- function(...) {
  suppressMessages(wf_autoweigh(...))
}

make_autoweigh_collapse_fixture <- function() {
  sample <- data.frame(
    id = paste0("r", 1:6),
    province = "A",
    edu = c("low", "mid", "mid", "high", "high", "high"),
    stringsAsFactors = FALSE
  )
  population <- data.frame(
    province = "A",
    edu = c("low", "mid", "high"),
    count = c(40, 30, 30),
    stringsAsFactors = FALSE
  )
  dims <- wf_dims(
    edu = c("low", "mid", "high"),
    .collapse = list(
      edu = list(
        step1 = c(low = "low_mid", mid = "low_mid", high = "high")
      )
    )
  )
  target <- wf_target_population(
    population,
    key_map = c(edu = "edu"),
    count = "count",
    dims = dims,
    by = "province"
  )
  list(sample = sample, target = target, dims = dims)
}

test_that("wf_autoweigh builds a target and returns an auditable raking result", {
  fixture <- make_weightflow_fixture()
  original_sample <- fixture$sample
  original_population <- fixture$pop

  result <- run_autoweigh(
    fixture$sample,
    fixture$pop,
    fixture$dims,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    by = "province",
    id = "id",
    interactive = FALSE
  )

  expect_s3_class(result, "wf_autoweigh_result")
  expect_s3_class(result$weights, "wf_weights")
  expect_s3_class(result$diagnostics, "wf_diagnostics")
  expect_s3_class(result$report, "wf_quality_report")
  expect_identical(result$method, "raking")
  expect_identical(result$language, "en")
  expect_identical(
    names(result$ledger),
    c("step", "action", "detail_key", "detail", "artifact_class", "time")
  )
  expect_identical(result$ledger$step, seq_len(nrow(result$ledger)))
  expect_true(all(c(
    "start", "target", "precheck", "trim", "calibrate", "done"
  ) %in% result$ledger$action))
  expect_true(all(nzchar(result$ledger$detail_key)))
  expect_length(result$artifacts, nrow(result$ledger))
  expect_identical(fixture$sample, original_sample)
  expect_identical(fixture$pop, original_population)
})

test_that("wf_autoweigh honors ready targets and explicit logit calibration", {
  fixture <- make_weightflow_fixture()

  result <- run_autoweigh(
    fixture$sample,
    fixture$target,
    fixture$dims,
    id = "id",
    method = "logit",
    bounds = c(0.2, 5),
    trim = NULL,
    interactive = FALSE
  )

  expect_identical(result$method, "logit")
  expect_identical(result$weights$provenance$method, "logit")
  expect_equal(result$weights$provenance$bounds, c(0.2, 5))
  expect_true("autoweigh_target_ready" %in% result$ledger$detail_key)
  expect_false("trim" %in% result$ledger$action)
})

test_that("auto method selects reviewed post-stratification when configured", {
  fixture <- make_poststrat_fixture()

  result <- run_autoweigh(
    fixture$sample,
    fixture$pop,
    fixture$dims,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    by = "province",
    id = "id",
    ladder = fixture$ladder,
    min_cell = 1,
    interactive = FALSE
  )

  expect_identical(result$method, "poststrat")
  expect_identical(result$weights$provenance$method, "poststrat")
  expect_true(length(result$target$joint) > 0)
  expect_true(all(c("cell_report", "collapse_map") %in% names(result$weights)))
})

test_that("wf_autoweigh applies only declared collapse remediations", {
  fixture <- make_autoweigh_collapse_fixture()
  sample <- subset(fixture$sample, edu != "low")
  original_target <- fixture$target

  result <- run_autoweigh(
    sample,
    fixture$target,
    fixture$dims,
    id = "id",
    trim = NULL,
    interactive = FALSE
  )

  expect_true("collapse" %in% result$ledger$action)
  expect_true("low_mid" %in% result$sample$edu)
  expect_true(
    "low_mid" %in% names(result$target$groups$A$margins$edu)
  )
  expect_identical(fixture$target, original_target)

  fixture$dims$collapse <- list()
  expect_error(
    run_autoweigh(
      sample,
      fixture$target,
      fixture$dims,
      id = "id",
      trim = NULL,
      interactive = FALSE
    ),
    class = "wf_error_feasibility"
  )
})

test_that("wf_autoweigh applies finite trim recommendations", {
  fixture <- make_weightflow_fixture()
  fixture$sample$base_weight <- 1
  fixture$sample$base_weight[1] <- 50

  result <- run_autoweigh(
    fixture$sample,
    fixture$target,
    fixture$dims,
    id = "id",
    max_deff = 2.1,
    max_residual = 0.04,
    caps = c(2, 3, 4),
    init_weight = "base_weight",
    tol = 1e-8,
    interactive = FALSE
  )

  expect_equal(result$weights$provenance$trim, c(0.05, 3))
  trim_step <- result$ledger[result$ledger$action == "trim", , drop = FALSE]
  expect_identical(trim_step$detail_key, "autoweigh_trim_applied")
  expect_true(any(result$ledger$artifact_class == "wf_auto_trim"))
})

test_that("wf_autoweigh records an unsuccessful trim search and continues", {
  fixture <- make_weightflow_fixture()
  fixture$sample$base_weight <- 1
  fixture$sample$base_weight[1] <- 50

  result <- run_autoweigh(
    fixture$sample,
    fixture$target,
    fixture$dims,
    id = "id",
    max_deff = 1,
    max_residual = 0,
    caps = c(2, 3),
    init_weight = "base_weight",
    interactive = FALSE
  )

  expect_null(result$weights$provenance$trim)
  expect_true(
    "autoweigh_trim_no_solution" %in% result$ledger$detail_key
  )
})

test_that("guided narration localizes without changing stable ledger keys", {
  fixture <- make_weightflow_fixture()

  english <- run_autoweigh(
    fixture$sample,
    fixture$target,
    fixture$dims,
    id = "id",
    trim = NULL,
    interactive = FALSE,
    lang = "en"
  )
  chinese <- run_autoweigh(
    fixture$sample,
    fixture$target,
    fixture$dims,
    id = "id",
    trim = NULL,
    interactive = FALSE,
    lang = "zh_CN"
  )

  expect_identical(chinese$language, "zh_CN")
  expect_identical(chinese$ledger$action, english$ledger$action)
  expect_identical(chinese$ledger$detail_key, english$ledger$detail_key)
  expect_false(identical(chinese$ledger$detail, english$ledger$detail))
  expect_identical(chinese$report$language, "zh_CN")
})

test_that("wf_autoweigh validates workflow-owned decisions", {
  fixture <- make_weightflow_fixture()

  expect_error(
    run_autoweigh(fixture$sample, fixture$pop, fixture$dims),
    class = "wf_error_schema"
  )
  expect_error(
    run_autoweigh(
      fixture$sample,
      fixture$target,
      fixture$dims,
      method = "poststrat",
      interactive = FALSE
    ),
    class = "wf_error_feasibility"
  )
  expect_error(
    run_autoweigh(
      fixture$sample,
      fixture$target,
      fixture$dims,
      interactive = FALSE,
      lang = "fr"
    ),
    class = "wf_error_input"
  )
})

test_that("interactive guided decisions can stop before calibration", {
  fixture <- make_autoweigh_collapse_fixture()
  sample <- subset(fixture$sample, edu != "low")
  testthat::local_mocked_bindings(
    .wf_autoweigh_confirm = function(prompt) FALSE,
    .package = "WFC"
  )

  expect_error(
    capture.output(
      run_autoweigh(
        sample,
        fixture$target,
        fixture$dims,
        id = "id",
        trim = NULL,
        interactive = TRUE
      )
    ),
    class = "wf_error_feasibility"
  )
})

test_that("wf_autoweigh_result prints localized ledger details", {
  fixture <- make_weightflow_fixture()
  result <- run_autoweigh(
    fixture$sample,
    fixture$target,
    fixture$dims,
    id = "id",
    trim = NULL,
    interactive = FALSE
  )

  expect_output(
    print(result),
    .wf_tr("autoweigh_print_header", lang = "en"),
    fixed = TRUE
  )
  expect_output(print(result), "precheck", fixed = TRUE)
})
