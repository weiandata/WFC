make_report_weights <- function() {
  fixture <- make_weightflow_fixture()
  list(
    weights = wf_rake(fixture$sample, fixture$target, id = "id", tol = 1e-8),
    target = fixture$target
  )
}

make_report_propensity <- function() {
  structure(
    list(
      data = data.frame(
        id = paste0("p", 1:4),
        group = ".all",
        weight = c(0.7, 0.9, 1.1, 1.3),
        feature = 1 / c(0.7, 0.9, 1.1, 1.3)
      ),
      log = data.frame(group = ".all", n = 4),
      achieved = NULL,
      overlap = list(
        threshold = 0.99,
        online = c(`0%` = 0.2, `50%` = 0.6, `100%` = 0.9),
        reference = c(`0%` = 0.1, `50%` = 0.4, `100%` = 0.8),
        n_boundary = 0L,
        n_online = 4L
      ),
      balance = data.frame(
        variable = "age",
        level = NA_character_,
        smd_unweighted = 0.4,
        smd_weighted = 0.1
      ),
      provenance = list(method = "propensity")
    ),
    class = c("wf_propensity_weights", "wf_weights")
  )
}

make_report_blend <- function() {
  structure(
    list(
      summary = data.frame(
        group = c("A", "__overall__"),
        estimate = c(0.55, 0.55),
        cell_weight = c(100, 100),
        n_cells = c(2L, 2L)
      ),
      lambda = data.frame(
        group = c("A", "A"),
        cell = c("urban", "rural"),
        lambda = c(0.6, 0.7),
        lambda_reason = c("neff", "neff"),
        lambda_trimmed = c(FALSE, TRUE)
      ),
      diagnostics = list(
        source_support = data.frame(
          group = c("A", "A"),
          cell = c("urban", "rural"),
          lambda_reason = c("neff", "neff")
        ),
        trimmed_lambda_count = 1L,
        one_source_cell_count = 0L
      ),
      sensitivity = data.frame(
        lambda = c(0.3, 0.4),
        group = c("__overall__", "__overall__"),
        estimate = c(0.50, 0.52),
        cell_weight = c(100, 100),
        n_cells = c(2L, 2L)
      ),
      provenance = list(method = "blend")
    ),
    class = "wf_blend_result"
  )
}

test_that("wf_report builds manager and analyst projections for weights", {
  fixture <- make_report_weights()

  manager <- wf_report(
    fixture$weights,
    target = fixture$target,
    audience = "manager"
  )
  analyst <- wf_report(
    fixture$weights,
    target = fixture$target,
    audience = "analyst"
  )

  expect_s3_class(manager, "wf_quality_report")
  expect_true(all(c(
    "group", "n", "ess", "deff", "verdict", "light",
    "publish_separately", "action"
  ) %in% names(manager$table)))
  expect_true("margin_maxerr" %in% names(analyst$table))
  expect_identical(manager$audience, "manager")
  expect_identical(analyst$audience, "analyst")
  expect_identical(manager$language, "en")
  expect_equal(as.data.frame(manager), manager$table)
})

test_that("wf_report carries propensity-specific overlap and balance sections", {
  report <- wf_report(make_report_propensity(), audience = "analyst")

  expect_identical(report$source_type, "weights")
  expect_true(all(c(
    "propensity_overlap", "propensity_quantiles", "propensity_balance"
  ) %in% names(report$sections)))
  expect_equal(report$sections$propensity_overlap$n_boundary, 0)
  expect_equal(report$sections$propensity_balance$variable, "age")
})

test_that("wf_report supports blend summaries and sensitivity", {
  report <- wf_report(make_report_blend(), audience = "manager")

  expect_identical(report$source_type, "blend")
  expect_true(all(c(
    "blend_lambda", "blend_sensitivity", "blend_source_support"
  ) %in% names(report$sections)))
  expect_true(all(c("light", "action") %in% names(report$table)))
  expect_equal(report$table$light[report$table$group == "A"], "yellow")
})

test_that("wf_report renders Markdown and escaped base HTML", {
  fixture <- make_report_weights()
  markdown <- wf_report(
    fixture$weights,
    target = fixture$target,
    output = "markdown"
  )
  expect_type(markdown, "character")
  expect_length(markdown, 1)
  expect_match(markdown, "# Weighting quality report", fixed = TRUE)
  expect_match(markdown, "| Group |", fixed = TRUE)

  unsafe <- structure(
    list(
      data = data.frame(
        id = 1:3,
        group = "<unsafe&>",
        weight = c(1, 2, 3),
        feature = 1 / c(1, 2, 3)
      ),
      log = data.frame(group = "<unsafe&>", n = 3),
      achieved = NULL,
      provenance = list(method = "test")
    ),
    class = "wf_weights"
  )
  html <- wf_report(unsafe, output = "html")
  expect_match(html, "<!DOCTYPE html>", fixed = TRUE)
  expect_match(html, "&lt;unsafe&amp;&gt;", fixed = TRUE)
  expect_false(grepl("<unsafe&>", html, fixed = TRUE))
})

test_that("wf_report localizes human text while preserving stable schemas", {
  fixture <- make_report_weights()
  chinese_catalog <- .wf_i18n_catalog("zh_CN")
  english <- wf_report(
    fixture$weights,
    target = fixture$target,
    audience = "manager",
    lang = "en"
  )
  chinese <- wf_report(
    fixture$weights,
    target = fixture$target,
    audience = "manager",
    lang = "zh_CN"
  )

  expect_identical(chinese$language, "zh_CN")
  expect_identical(names(chinese$table), names(english$table))
  expect_identical(chinese$table$verdict, english$table$verdict)
  expect_true("verdict_label" %in% names(chinese$table))
  action_keys <- c(
    "action_weights_green",
    "action_weights_yellow",
    "action_weights_red"
  )
  expect_true(all(chinese$table$action %in% unname(chinese_catalog[action_keys])))

  markdown <- wf_report(
    fixture$weights,
    target = fixture$target,
    lang = "zh_CN",
    output = "markdown"
  )
  html <- wf_report(
    fixture$weights,
    target = fixture$target,
    lang = "zh_CN",
    output = "html"
  )
  expect_match(
    markdown,
    paste0("# ", unname(chinese_catalog["report_title"])),
    fixed = TRUE
  )
  expect_match(
    markdown,
    paste0("| ", unname(chinese_catalog["column_group"]), " |"),
    fixed = TRUE
  )
  expect_match(
    html,
    paste0("<title>", unname(chinese_catalog["report_title"]), "</title>"),
    fixed = TRUE
  )
})

test_that("wf_report honors the configured default language", {
  fixture <- make_report_weights()
  old <- options(wfc.lang = "zh_CN")
  on.exit(options(old), add = TRUE)

  report <- wf_report(fixture$weights, target = fixture$target)
  expect_identical(report$language, "zh_CN")
  expect_identical(
    report$title,
    unname(.wf_i18n_catalog("zh_CN")["report_title"])
  )
})

test_that("wf_report writes rendered output and invisibly returns the object", {
  fixture <- make_report_weights()
  path <- tempfile(fileext = ".md")

  result <- withVisible(wf_report(
    fixture$weights,
    target = fixture$target,
    output = "markdown",
    file = path
  ))

  expect_false(result$visible)
  expect_s3_class(result$value, "wf_quality_report")
  expect_true(file.exists(path))
  expect_match(paste(readLines(path), collapse = "\n"), "Weighting quality report")
})

test_that("wf_report validates sources, language, output and file combinations", {
  fixture <- make_report_weights()

  expect_error(wf_report(list()), class = "wf_error_input")
  expect_error(
    wf_report(fixture$weights, lang = "fr"),
    class = "wf_error_input"
  )
  expect_error(
    wf_report(fixture$weights, output = "object", file = tempfile()),
    class = "wf_error_input"
  )
})

test_that("wf_quality_report print renders the report", {
  fixture <- make_report_weights()
  report <- wf_report(fixture$weights, target = fixture$target)

  expect_output(print(report), "Weighting quality report")
  expect_output(print(report), "publishable separately")
})
