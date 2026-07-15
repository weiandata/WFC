test_that("2.0 development preserves the historical 1.0 API freeze", {
  expect_equal(as.character(utils::packageVersion("WFC")), "2.0.0.9000")

  freeze <- system.file("stability/api-freeze.md", package = "WFC")
  expect_true(nzchar(freeze))
  text <- readLines(freeze, warn = FALSE)

  expect_true(any(grepl("WFC 1.0 API Freeze", text, fixed = TRUE)))
  expect_true(any(grepl("wf_rake(sample, target", text, fixed = TRUE)))
  expect_true(any(grepl("parallel = FALSE, progress = FALSE", text, fixed = TRUE)))
  expect_true(any(grepl("wf_warning_deprecated", text, fixed = TRUE)))
  expect_true(any(grepl("WFCstudio beta targets WFC `>= 1.0.0, < 2.0.0`", text, fixed = TRUE)))
})

test_that("deprecated API warnings use the frozen class", {
  expect_warning(
    .wf_warn_deprecated(
      "old_arg is deprecated; use new_arg.",
      feature = "old_arg",
      replacement = "new_arg"
    ),
    class = "wf_warning_deprecated"
  )
})
