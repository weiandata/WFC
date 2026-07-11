test_that("wf_poststrat matches joint cell population totals", {
  fixture <- make_poststrat_fixture()

  weights <- wf_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 1,
    ladder = fixture$ladder,
    id = "id"
  )

  expect_s3_class(weights, "wf_weights")
  expect_equal(weights$provenance$method, "poststrat")
  expect_true(all(weights$data$weight >= 0))
  expect_equal(sum(weights$data$weight), fixture$target$groups$A$total, tolerance = 1e-8)
  expect_true(all(c("cell_report", "collapse_map") %in% names(weights)))
  expect_equal(max(weights$log$total_dev), 0, tolerance = 1e-8)
})

test_that("wf_poststrat rejects a missing init_weight column with a classed error", {
  fixture <- make_poststrat_fixture()

  expect_error(
    wf_poststrat(
      fixture$sample,
      fixture$target,
      min_cell = 1,
      ladder = fixture$ladder,
      init_weight = "no_such_column",
      id = "id"
    ),
    class = "wf_error_schema"
  )
})

test_that("wf_poststrat preserves initial weight ratios within resolved cells", {
  fixture <- make_poststrat_fixture()
  fixture$sample$base_w <- seq_len(nrow(fixture$sample))

  weights <- wf_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 2,
    ladder = fixture$ladder,
    init_weight = "base_w",
    id = "id"
  )

  merged <- merge(weights$data, fixture$sample[, c("id", "base_w")], by = "id")
  by_cell <- split(merged, merged$resolved_cell)
  checked <- FALSE
  for (d in by_cell) {
    if (nrow(d) >= 2 && all(d$weight > 0)) {
      expect_equal(d$weight[1] / d$weight[2], d$base_w[1] / d$base_w[2], tolerance = 1e-8)
      checked <- TRUE
      break
    }
  }
  expect_true(checked)
})

test_that("wf_poststrat can flag or reject empty cells", {
  fixture <- make_poststrat_fixture()
  fixture$sample <- fixture$sample[fixture$sample$gender == "female", ]

  expect_error(
    suppressWarnings(wf_poststrat(
      fixture$sample,
      fixture$target,
      min_cell = 1,
      ladder = fixture$ladder,
      empty_cell = "error"
    )),
    class = "wf_error_feasibility"
  )

  flagged <- suppressWarnings(wf_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 1,
    ladder = fixture$ladder,
    empty_cell = "flag"
  ))
  expect_lt(sum(flagged$data$weight), fixture$target$groups$A$total)
  expect_gt(flagged$log$total_dev, 0)
})

test_that("wf_diagnose supports poststrat weights", {
  fixture <- make_poststrat_fixture()

  weights <- wf_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 1,
    ladder = fixture$ladder,
    id = "id"
  )
  diag <- wf_diagnose(weights, target = fixture$target)

  expect_s3_class(diag, "wf_diagnostics")
  expect_true(all(c("ess", "deff", "verdict") %in% names(diag$table)))
  expect_true(all(diag$table$converged))
  expect_false("margin_maxerr" %in% names(diag$table))
})
