make_blend_weights <- function(source = "online",
                               group = c("A", "A", "A", "A"),
                               cell = c("urban", "urban", "rural", "rural"),
                               weight = c(1, 1, 1, 1),
                               outcome = c(1, 0, 1, 0)) {
  data <- data.frame(
    id = paste0(source, "_", seq_along(group)),
    group = group,
    cell = cell,
    weight = weight,
    outcome = outcome,
    stringsAsFactors = FALSE
  )
  structure(
    list(
      data = data,
      log = data.frame(
        group = unique(group),
        iterations = NA_integer_,
        converged = TRUE,
        trimmed = 0L,
        stringsAsFactors = FALSE
      ),
      achieved = NULL,
      provenance = list(method = source, created = Sys.time())
    ),
    class = "wf_weights"
  )
}

test_that("wf_blend is exported", {
  expect_true("wf_blend" %in% getNamespaceExports("WFC"))
  expect_true(is.function(wf_blend))
})

test_that("wf_blend validates source objects and required columns", {
  online <- make_blend_weights("online")
  offline <- make_blend_weights("offline")

  expect_error(
    wf_blend(list(), offline, by_cell = "cell", outcome = "outcome"),
    class = "wf_error_input"
  )
  expect_error(
    wf_blend(online, list(), by_cell = "cell", outcome = "outcome"),
    class = "wf_error_input"
  )

  missing_group <- online
  missing_group$data$group <- NULL
  expect_error(
    wf_blend(missing_group, offline, by_cell = "cell", outcome = "outcome"),
    class = "wf_error_schema"
  )

  missing_cell <- offline
  missing_cell$data$cell <- NULL
  expect_error(
    wf_blend(online, missing_cell, by_cell = "cell", outcome = "outcome"),
    class = "wf_error_schema"
  )

  missing_weight <- offline
  missing_weight$data$weight <- NULL
  expect_error(
    wf_blend(online, missing_weight, by_cell = "cell", outcome = "outcome"),
    class = "wf_error_schema"
  )

  missing_outcome <- online
  missing_outcome$data$outcome <- NULL
  expect_error(
    wf_blend(missing_outcome, offline, by_cell = "cell", outcome = "outcome"),
    class = "wf_error_schema"
  )
})

test_that("wf_blend validates weights, outcome, lambda, level, and trim settings", {
  online <- make_blend_weights("online")
  offline <- make_blend_weights("offline")

  bad_weight <- online
  bad_weight$data$weight[[1]] <- -1
  expect_error(
    wf_blend(bad_weight, offline, by_cell = "cell", outcome = "outcome"),
    class = "wf_error_input"
  )

  bad_outcome <- online
  bad_outcome$data$outcome <- as.character(bad_outcome$data$outcome)
  expect_error(
    wf_blend(bad_outcome, offline, by_cell = "cell", outcome = "outcome"),
    class = "wf_error_input"
  )

  expect_error(
    wf_blend(online, offline, by_cell = "cell", outcome = "outcome", lambda = "median"),
    class = "wf_error_input"
  )
  expect_error(
    wf_blend(online, offline, by_cell = "cell", outcome = "outcome", level = "province"),
    class = "wf_error_input"
  )
  expect_error(
    wf_blend(
      online,
      offline,
      by_cell = "cell",
      outcome = "outcome",
      trim_lambda = c(0.9, 0.1)
    ),
    class = "wf_error_input"
  )
  expect_error(
    wf_blend(online, offline, by_cell = "cell", outcome = "outcome", lambda = "fixed"),
    class = "wf_error_input"
  )
})

test_that("wf_blend computes source estimates before fusing", {
  online <- make_blend_weights(
    "online",
    group = c("A", "A"),
    cell = c("urban", "urban"),
    weight = c(100, 100),
    outcome = c(1, 0)
  )
  offline <- make_blend_weights(
    "offline",
    group = c("A", "A"),
    cell = c("urban", "urban"),
    weight = c(1, 1),
    outcome = c(0, 0)
  )

  out <- wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = "outcome",
    lambda = "fixed",
    lambda_fixed = 0.5,
    sensitivity = FALSE
  )

  stacked_weight <- c(online$data$weight, offline$data$weight)
  stacked_outcome <- c(online$data$outcome, offline$data$outcome)
  stacked <- sum(stacked_weight * stacked_outcome) / sum(stacked_weight)

  expect_s3_class(out, "wf_blend_result")
  expect_equal(out$estimates$estimate_online, 0.5, tolerance = 1e-10)
  expect_equal(out$estimates$estimate_offline, 0, tolerance = 1e-10)
  expect_equal(out$estimates$lambda, 0.5, tolerance = 1e-10)
  expect_equal(out$estimates$estimate, 0.25, tolerance = 1e-10)
  expect_false(isTRUE(all.equal(out$estimates$estimate, stacked)))
})

test_that("wf_blend uses effective sample size for neff lambda", {
  online <- make_blend_weights(
    "online",
    group = c("A", "A", "A"),
    cell = c("urban", "urban", "urban"),
    weight = c(1, 1, 1),
    outcome = c(1, 1, 0)
  )
  offline <- make_blend_weights(
    "offline",
    group = c("A", "A"),
    cell = c("urban", "urban"),
    weight = c(2, 2),
    outcome = c(0, 0)
  )

  out <- wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = "outcome",
    lambda = "neff",
    trim_lambda = c(0, 1),
    sensitivity = FALSE
  )

  expect_equal(out$estimates$neff_online, 3, tolerance = 1e-10)
  expect_equal(out$estimates$neff_offline, 2, tolerance = 1e-10)
  expect_equal(out$estimates$lambda, 3 / 5, tolerance = 1e-10)
  expect_equal(out$estimates$estimate, (3 / 5) * (2 / 3), tolerance = 1e-10)
})

test_that("wf_blend uses inverse-variance lambda", {
  online <- make_blend_weights(
    "online",
    group = c("A", "A"),
    cell = c("urban", "urban"),
    weight = c(1, 1),
    outcome = c(1, 0)
  )
  offline <- make_blend_weights(
    "offline",
    group = c("A", "A"),
    cell = c("urban", "urban"),
    weight = c(1, 1),
    outcome = c(1, 1)
  )

  out <- wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = "outcome",
    lambda = "inverse_variance",
    trim_lambda = c(0, 1),
    sensitivity = FALSE
  )

  expect_equal(out$estimates$variance_online, 0.125, tolerance = 1e-10)
  expect_equal(out$estimates$variance_offline, 0, tolerance = 1e-10)
  expect_equal(out$estimates$lambda, 0, tolerance = 1e-10)
  expect_equal(out$estimates$estimate, 1, tolerance = 1e-10)
})

test_that("wf_blend applies fixed lambda tables by cell and group", {
  online <- make_blend_weights(
    "online",
    group = c("A", "A", "B", "B"),
    cell = c("urban", "rural", "urban", "rural"),
    outcome = c(1, 1, 0, 0)
  )
  offline <- make_blend_weights(
    "offline",
    group = c("A", "A", "B", "B"),
    cell = c("urban", "rural", "urban", "rural"),
    outcome = c(0, 0, 1, 1)
  )

  by_cell_lambda <- data.frame(
    group = c("A", "A", "B", "B"),
    cell = c("urban", "rural", "urban", "rural"),
    lambda = c(0.2, 0.4, 0.6, 0.8),
    stringsAsFactors = FALSE
  )
  out_cell <- wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = "outcome",
    lambda = "fixed",
    lambda_fixed = by_cell_lambda,
    level = "cell",
    sensitivity = FALSE
  )
  out_cell <- out_cell$estimates[order(out_cell$estimates$group, out_cell$estimates$cell), ]

  expect_equal(out_cell$lambda, c(0.4, 0.2, 0.8, 0.6), tolerance = 1e-10)

  by_group_lambda <- data.frame(
    group = c("A", "B"),
    lambda = c(0.25, 0.75),
    stringsAsFactors = FALSE
  )
  out_group <- wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = "outcome",
    lambda = "fixed",
    lambda_fixed = by_group_lambda,
    level = "group",
    sensitivity = FALSE
  )
  out_group <- out_group$estimates[order(out_group$estimates$group, out_group$estimates$cell), ]

  expect_equal(out_group$lambda, c(0.25, 0.25, 0.75, 0.75), tolerance = 1e-10)
})

test_that("wf_blend computes group-level data-driven lambda and trims two-source cells", {
  online <- make_blend_weights(
    "online",
    group = c("A", "A", "A", "B"),
    cell = c("urban", "urban", "rural", "urban"),
    weight = c(1, 1, 1, 100),
    outcome = c(1, 1, 1, 1)
  )
  offline <- make_blend_weights(
    "offline",
    group = c("A", "A", rep("B", 10)),
    cell = c("urban", "rural", rep("urban", 10)),
    weight = rep(1, 12),
    outcome = rep(0, 12)
  )

  expect_warning(
    out <- wf_blend(
      online,
      offline,
      by_cell = "cell",
      outcome = "outcome",
      lambda = "neff",
      level = "group",
      trim_lambda = c(0.2, 0.8),
      sensitivity = FALSE
    ),
    class = "wf_warning_quality"
  )

  expect_equal(out$estimates$lambda[out$estimates$group == "A"], c(0.6, 0.6), tolerance = 1e-10)
  expect_equal(out$estimates$lambda[out$estimates$group == "B"], 0.2, tolerance = 1e-10)
  expect_true(any(out$estimates$lambda_trimmed))
})

test_that("wf_blend handles one-source cells and rejects no-source outcome cells", {
  online <- make_blend_weights(
    "online",
    group = c("A", "A"),
    cell = c("online_only", "shared"),
    weight = c(1, 1),
    outcome = c(1, 1)
  )
  offline <- make_blend_weights(
    "offline",
    group = c("A", "A"),
    cell = c("offline_only", "shared"),
    weight = c(1, 1),
    outcome = c(0, 0)
  )

  expect_warning(
    out <- wf_blend(
      online,
      offline,
      by_cell = "cell",
      outcome = "outcome",
      lambda = "neff",
      sensitivity = FALSE
    ),
    class = "wf_warning_quality"
  )

  one_source <- out$estimates[out$estimates$cell %in% c("online_only", "offline_only"), ]
  expect_equal(one_source$lambda[one_source$cell == "online_only"], 1, tolerance = 1e-10)
  expect_equal(one_source$lambda[one_source$cell == "offline_only"], 0, tolerance = 1e-10)
  expect_equal(out$diagnostics$one_source_cell_count, 2)

  bad_online <- online
  bad_offline <- offline
  bad_online$data$outcome[bad_online$data$cell == "shared"] <- NA_real_
  bad_offline$data$outcome[bad_offline$data$cell == "shared"] <- NA_real_
  expect_error(
    suppressWarnings(
      wf_blend(bad_online, bad_offline, by_cell = "cell", outcome = "outcome", sensitivity = FALSE)
    ),
    class = "wf_error_feasibility"
  )
})

test_that("wf_blend outcome-null mode returns a cell ledger instead of wf_weights", {
  online <- make_blend_weights("online")
  offline <- make_blend_weights("offline")

  out <- wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = NULL,
    lambda = "fixed",
    lambda_fixed = 0.7,
    sensitivity = FALSE
  )

  expect_s3_class(out, "wf_blend_result")
  expect_false(inherits(out, "wf_weights"))
  expect_equal(nrow(out$estimates), 0)
  expect_true(all(c("group", "cell", "lambda", "fused_cell_total") %in% names(out$cell_weights)))
  expect_equal(out$cell_weights$lambda, rep(0.7, nrow(out$cell_weights)), tolerance = 1e-10)
})

test_that("wf_blend builds summaries, sensitivity output, print output, and provenance", {
  online <- make_blend_weights(
    "online",
    group = c("A", "A", "B", "B"),
    cell = c("urban", "rural", "urban", "rural"),
    weight = c(1, 1, 1, 1),
    outcome = c(1, 1, 0, 0)
  )
  offline <- make_blend_weights(
    "offline",
    group = c("A", "A", "B", "B"),
    cell = c("urban", "rural", "urban", "rural"),
    weight = c(1, 1, 1, 1),
    outcome = c(0, 0, 1, 1)
  )

  out <- wf_blend(
    online,
    offline,
    by_cell = "cell",
    outcome = "outcome",
    lambda = "fixed",
    lambda_fixed = 0.25,
    sensitivity = TRUE
  )

  expect_true(all(c("group", "estimate", "cell_weight") %in% names(out$summary)))
  expect_true(all(c("lambda", "group", "estimate") %in% names(out$sensitivity)))
  expect_equal(sort(unique(out$sensitivity$lambda)), seq(0.3, 0.9, by = 0.1), tolerance = 1e-10)
  expect_equal(out$provenance$method, "blend")
  expect_equal(out$provenance$sources$online$method, "online")
  expect_equal(out$provenance$sources$offline$method, "offline")
  expect_true(length(out$provenance$assumptions) >= 3)
  expect_output(print(out), "<wf_blend_result>")
  expect_output(print(out), "lambda")
})
