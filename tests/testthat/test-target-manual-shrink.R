test_that("WFC 2.0 does not export subjective target constructors", {
  exports <- getNamespaceExports("WFC")

  expect_false("wf_target_manual" %in% exports)
  expect_false("wf_target_shrink" %in% exports)
})

test_that("migration guidance gives removed target behavior no workaround", {
  path <- if (file.exists("DESCRIPTION")) {
    "docs/migration/wfc-1-to-2.md"
  } else {
    file.path("..", "..", "docs/migration/wfc-1-to-2.md")
  }
  skip_if_not(file.exists(path), "migration guide is not installed")
  guidance <- readLines(path, warn = FALSE)

  expect_true(any(grepl("wf_target_manual()", guidance, fixed = TRUE)))
  expect_true(any(grepl("wf_target_shrink()", guidance, fixed = TRUE)))
  expect_true(any(grepl("No supported replacement", guidance, fixed = TRUE)))
})
