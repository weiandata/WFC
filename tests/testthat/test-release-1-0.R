test_that("1.1 release preserves the 1.0 API freeze document", {
  expect_equal(as.character(utils::packageVersion("WFC")), "1.1.0")

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
