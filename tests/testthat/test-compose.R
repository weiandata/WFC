make_compose_stage <- function(ids = paste0("r", 1:4),
                               groups = c("A", "A", "B", "B"),
                               weights = c(1, 2, 3, 4),
                               method = "stage",
                               row_order = NULL,
                               drop_id = FALSE) {
  data <- data.frame(
    id = ids,
    group = groups,
    weight = weights,
    feature = 1 / weights,
    stringsAsFactors = FALSE
  )
  if (!is.null(row_order)) {
    data <- data[row_order, , drop = FALSE]
  }
  if (drop_id) {
    data$id <- NULL
  }
  structure(
    list(
      data = data,
      log = data.frame(
        group = unique(data$group),
        iterations = NA_integer_,
        converged = TRUE,
        trimmed = 0L,
        stringsAsFactors = FALSE
      ),
      achieved = NULL,
      provenance = list(method = method, created = Sys.time())
    ),
    class = "wf_weights"
  )
}

test_that("wf_compose multiplies stages by id and records provenance", {
  stage1 <- make_compose_stage(weights = c(2, 3, 4, 5), method = "design")
  stage2 <- make_compose_stage(weights = c(0.5, 2, 1.5, 1), method = "adjustment")

  out <- wf_compose(stage1, stage2)

  expect_s3_class(out, "wf_weights")
  expect_equal(out$data$id, paste0("r", 1:4))
  expect_equal(out$data$group, c("A", "A", "B", "B"))
  expect_equal(out$data$weight, c(1, 6, 6, 5), tolerance = 1e-10)
  expect_equal(out$data$feature, 1 / out$data$weight, tolerance = 1e-10)
  expect_equal(out$achieved, NULL)
  expect_equal(out$provenance$method, "compose")
  expect_equal(out$provenance$mode, "compose")
  expect_equal(length(out$provenance$stages), 2)
  expect_equal(out$provenance$stages[[1]]$provenance$method, "design")
  expect_equal(out$provenance$stages[[2]]$provenance$method, "adjustment")
  expect_equal(out$provenance$compose$stage_count, 2)
  expect_equal(out$provenance$compose$normalize, "none")
  expect_true(all(c("iterations", "converged", "trimmed") %in% names(out$log)))
})

test_that("wf_compose is invariant to input row order when ids match", {
  stage1 <- make_compose_stage(weights = c(2, 3, 4, 5))
  stage2 <- make_compose_stage(
    weights = c(0.5, 2, 1.5, 1),
    row_order = c(4, 2, 1, 3)
  )

  out <- wf_compose(stage1, stage2)

  expect_equal(out$data$id, paste0("r", 1:4))
  expect_equal(out$data$weight, c(1, 6, 6, 5), tolerance = 1e-10)
})

test_that("wf_compose supports row-order composition when no stage has ids", {
  stage1 <- make_compose_stage(
    ids = paste0("r", 1:3),
    weights = c(2, 3, 4),
    groups = c("A", "A", "B"),
    drop_id = TRUE
  )
  stage2 <- make_compose_stage(
    ids = paste0("r", 1:3),
    weights = c(0.5, 2, 1.5),
    groups = c("A", "A", "B"),
    drop_id = TRUE
  )

  out <- wf_compose(stage1, stage2)

  expect_equal(out$data$id, as.character(1:3))
  expect_equal(out$data$weight, c(1, 6, 6), tolerance = 1e-10)
})

test_that("wf_compose normalizes composed weights", {
  stage1 <- make_compose_stage(weights = c(2, 3, 4, 5))
  stage2 <- make_compose_stage(weights = c(0.5, 2, 1.5, 1))

  mean1 <- wf_compose(stage1, stage2, normalize = "mean1")
  sum_norm <- wf_compose(stage1, stage2, normalize = "sum")

  expect_equal(mean(mean1$data$weight), 1, tolerance = 1e-10)
  expect_equal(sum(sum_norm$data$weight), sum(stage1$data$weight), tolerance = 1e-10)
  expect_equal(mean1$provenance$compose$normalize, "mean1")
  expect_equal(sum_norm$provenance$compose$normalize, "sum")
})

test_that("wf_compose rejects unsafe inputs", {
  stage1 <- make_compose_stage()
  stage2 <- make_compose_stage()

  expect_error(wf_compose(stage1), class = "wf_error_input")
  expect_error(wf_compose(stage1, list()), class = "wf_error_input")
  expect_error(wf_compose(stage1, stage2, normalize = "median"), class = "wf_error_input")

  missing_group <- stage2
  missing_group$data$group <- NULL
  expect_error(wf_compose(stage1, missing_group), class = "wf_error_schema")

  duplicate_ids <- make_compose_stage(ids = c("r1", "r1", "r3", "r4"))
  expect_error(wf_compose(stage1, duplicate_ids), class = "wf_error_input")

  missing_ids <- make_compose_stage(ids = c("r1", NA, "r3", "r4"))
  expect_error(wf_compose(stage1, missing_ids), class = "wf_error_input")

  different_ids <- make_compose_stage(ids = c("r1", "r2", "r3", "rx"))
  expect_error(wf_compose(stage1, different_ids), class = "wf_error_input")

  group_mismatch <- make_compose_stage(groups = c("A", "A", "A", "B"))
  expect_error(wf_compose(stage1, group_mismatch), class = "wf_error_input")

  bad_weights <- make_compose_stage(weights = c(1, Inf, 1, 1))
  expect_error(wf_compose(stage1, bad_weights), class = "wf_error_input")

  non_positive_weights <- make_compose_stage(weights = c(1, 0, 1, 1))
  expect_error(wf_compose(stage1, non_positive_weights), class = "wf_error_input")
})

test_that("wf_compose requires consistent id-column availability", {
  with_id <- make_compose_stage()
  without_id <- make_compose_stage(drop_id = TRUE)

  expect_error(wf_compose(with_id, without_id), class = "wf_error_input")
  expect_error(wf_compose(without_id, with_id), class = "wf_error_input")
  expect_error(wf_compose(without_id, without_id, id = "id"), class = "wf_error_schema")
})

test_that("composed weights remain compatible with print and diagnose", {
  stage1 <- make_compose_stage(weights = c(2, 3, 4, 5))
  stage2 <- make_compose_stage(weights = c(0.5, 2, 1.5, 1))

  out <- wf_compose(stage1, stage2)
  diag <- wf_diagnose(out)

  expect_output(print(out), "<wf_weights>")
  expect_s3_class(diag, "wf_diagnostics")
  expect_true(all(c("ess", "deff", "verdict") %in% names(diag$table)))
  expect_false("margin_maxerr" %in% names(diag$table))
  expect_true(all(diag$table$converged))
})

test_that("wf_compose is available as a foundation pipeline API", {
  expect_true(is.function(wf_compose))
})
