root_file <- function(path) {
  candidates <- c(path, file.path("..", "..", path))
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0) {
    testthat::skip(sprintf("%s is only available in the development checkout", path))
  }
  normalizePath(existing[[1]], mustWork = TRUE)
}

test_that("git ignore protects private source data formats", {
  gitignore <- readLines(root_file(".gitignore"), warn = FALSE)

  expect_true("*.xlsx" %in% gitignore)
  expect_true("*.RData" %in% gitignore)
  expect_true("private-data/" %in% gitignore)
})

test_that("R build ignore excludes development-only local files", {
  rbuildignore <- readLines(root_file(".Rbuildignore"), warn = FALSE)

  expect_true("^private-data$" %in% rbuildignore)
  expect_true("^data-raw$" %in% rbuildignore)
  expect_true("^\\.codegraph$" %in% rbuildignore)
})
