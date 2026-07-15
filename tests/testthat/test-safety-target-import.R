make_safe_target_files <- function(demo_only = FALSE, bad_checksum = FALSE) {
  path <- tempfile("wf-safe-target-")
  dir.create(path)

  data_file <- file.path(path, "population.csv")
  source_file <- file.path(path, "population.source.dcf")
  data <- data.frame(
    sex = c("F", "M"),
    count = c(52, 48),
    stringsAsFactors = FALSE
  )
  utils::write.csv(data, data_file, row.names = FALSE)

  checksum <- .wf_sha256_file(data_file)
  if (bad_checksum) {
    checksum <- paste0(strrep("0", 63), "1")
  }
  source <- c(
    publisher = "Synthetic example publisher",
    dataset_title = "Synthetic population margins",
    citation = "Synthetic fixture; not an external authority",
    reference_period = "2026",
    population_scope = "Synthetic adults",
    retrieved_at = "2026-07-15",
    license = "CC0-1.0",
    checksum_algorithm = "sha256",
    checksum = checksum,
    transformation = "No transformation",
    selected_before_outcomes = "true",
    demo_only = if (demo_only) "true" else "false"
  )
  writeLines(sprintf("%s: %s", names(source), source), source_file)

  list(
    data = data_file,
    source = source_file,
    dims = wf_dims(sex = c("F", "M"))
  )
}

make_safe_reference_files <- function(extra_outcome = FALSE) {
  path <- tempfile("wf-safe-reference-")
  dir.create(path)

  data_file <- file.path(path, "reference.csv")
  source_file <- file.path(path, "reference.source.dcf")
  data <- data.frame(
    sex = c("F", "F", "M", "M"),
    inclusion_probability = c(0.5, 0.5, 0.25, 0.25),
    stringsAsFactors = FALSE
  )
  if (extra_outcome) {
    data$outcome <- c(1, 0, 1, 0)
  }
  utils::write.csv(data, data_file, row.names = FALSE)

  source <- c(
    publisher = "Synthetic example publisher",
    dataset_title = "Synthetic reference sample",
    citation = "Synthetic fixture; not an external authority",
    reference_period = "2026",
    population_scope = "Synthetic adults",
    retrieved_at = "2026-07-15",
    license = "CC0-1.0",
    checksum_algorithm = "sha256",
    checksum = .wf_sha256_file(data_file),
    transformation = "No transformation",
    selected_before_outcomes = "true",
    demo_only = "false"
  )
  writeLines(sprintf("%s: %s", names(source), source), source_file)

  list(
    data = data_file,
    source = source_file,
    dims = wf_dims(sex = c("F", "M"))
  )
}

test_that("complete source evidence creates a verified target", {
  f <- make_safe_target_files(demo_only = FALSE)

  x <- wf_import_target(
    f$data,
    f$source,
    f$dims,
    c(sex = "sex"),
    "count"
  )

  expect_s3_class(x, "wf_verified_target")
  expect_false(x$demo_only)
  expect_identical(x$source_type, "population")
  expect_match(x$identity, "^[0-9a-f]{64}$")
  expect_false(is.null(x$joint))
})

test_that("bad checksums block target import", {
  f <- make_safe_target_files(bad_checksum = TRUE)

  expect_error(
    wf_import_target(
      f$data,
      f$source,
      f$dims,
      c(sex = "sex"),
      "count"
    ),
    class = "wf_error_safety"
  )
})

test_that("production use of demo targets blocks", {
  f <- make_safe_target_files(demo_only = TRUE)

  expect_error(
    wf_import_target(
      f$data,
      f$source,
      f$dims,
      c(sex = "sex"),
      "count"
    ),
    class = "wf_error_safety"
  )
})

test_that("reference targets import only declared design columns", {
  f <- make_safe_reference_files()

  x <- wf_import_reference(
    f$data,
    f$source,
    f$dims,
    "inclusion_probability"
  )

  expect_s3_class(x, "wf_verified_target")
  expect_identical(x$source_type, "reference")
})

test_that("unassigned reference outcome columns block", {
  f <- make_safe_reference_files(extra_outcome = TRUE)

  expect_error(
    wf_import_reference(
      f$data,
      f$source,
      f$dims,
      "inclusion_probability"
    ),
    class = "wf_error_safety"
  )
})

test_that("CSV and Excel examples have separate evidence and equal margins", {
  skip_if_not_installed("openxlsx")
  path <- tempfile("wf-target-templates-")
  dir.create(path)
  csv_file <- file.path(path, "target.csv")
  xlsx_file <- file.path(path, "target.xlsx")
  dims <- wf_dims(sex = c("F", "M"))

  csv_files <- wf_target_template(csv_file, dims, example = TRUE)
  xlsx_files <- wf_target_template(xlsx_file, dims, example = TRUE)
  csv_target <- wf_import_target(
    csv_files$data_file,
    csv_files$source_file,
    dims,
    c(sex = "sex"),
    "count",
    production = FALSE
  )
  xlsx_target <- wf_import_target(
    xlsx_files$data_file,
    xlsx_files$source_file,
    dims,
    c(sex = "sex"),
    "count",
    production = FALSE
  )

  expect_equal(csv_target$groups, xlsx_target$groups)
  expect_true(file.exists(paste0(csv_file, ".source.dcf")))
  expect_true(file.exists(paste0(xlsx_file, ".source.dcf")))
  expect_false(identical(
    csv_target$evidence$data_checksum,
    xlsx_target$evidence$data_checksum
  ))
})

test_that("blank templates require source details before import", {
  path <- tempfile(fileext = ".csv")
  dims <- wf_dims(sex = c("F", "M"))

  files <- wf_target_template(path, dims)

  expect_equal(nrow(utils::read.csv(path)), 0)
  expect_error(
    wf_import_target(
      files$data_file,
      files$source_file,
      dims,
      c(sex = "sex"),
      "count"
    ),
    class = "wf_error_safety"
  )
})

test_that("bundled CSV and Excel import examples remain usable", {
  skip_if_not_installed("openxlsx")
  path <- system.file("extdata", package = "WFC")
  dims <- wf_dims(sex = c("F", "M"), age = c("18-34", "35+"))
  csv_file <- file.path(path, "safe-target-example.csv")
  xlsx_file <- file.path(path, "safe-target-example.xlsx")

  csv_target <- wf_import_target(
    csv_file,
    paste0(csv_file, ".source.dcf"),
    dims,
    c(sex = "sex", age = "age"),
    "count",
    production = FALSE
  )
  xlsx_target <- wf_import_target(
    xlsx_file,
    paste0(xlsx_file, ".source.dcf"),
    dims,
    c(sex = "sex", age = "age"),
    "count",
    production = FALSE
  )

  expect_equal(csv_target$groups, xlsx_target$groups)
})
