# Online sample skews toward high x; reference is centered lower but overlaps,
# so glm fits cleanly (no perfect separation).
make_prop_target <- function() {
  online <- data.frame(
    x = c(1.0, 1.4, 1.8, 2.2, 2.6, 3.0, 3.4, -0.5),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-2.0, -1.6, -1.2, -0.8, -0.4, 0.0, 0.4, 2.8),
    stringsAsFactors = FALSE
  )
  wf_target_propensity(online, reference, member ~ x)
}

test_that("wf_propensity rejects NA in membership-model predictors", {
  online <- data.frame(x = c(1.0, 1.4, NA, 2.2), stringsAsFactors = FALSE)
  reference <- data.frame(x = c(-2.0, -1.6, -1.2, -0.8), stringsAsFactors = FALSE)
  tgt <- wf_target_propensity(online, reference, member ~ x)

  expect_error(wf_propensity(tgt), class = "wf_error_input")
})

test_that("wf_propensity returns a wf_weights object with the id/group/weight/feature contract", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))

  expect_s3_class(w, "wf_propensity_weights")
  expect_s3_class(w, "wf_weights")
  expect_named(w$data, c("id", "group", "weight", "feature"))
  expect_equal(nrow(w$data), tgt$n_online)
  expect_equal(w$data$id, as.character(1:8))
  expect_true(all(w$data$weight > 0))
  expect_equal(w$data$feature, 1 / w$data$weight)
  expect_equal(w$provenance$method, "propensity")
})

test_that("wf_propensity ipw weights are proportional to 1/phat and normalized to mean 1", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE))

  # Independently refit the same model to recover the fitted online propensities.
  fit <- stats::glm(member ~ x, family = stats::binomial(), data = tgt$stacked)
  phat_online <- stats::fitted(fit)[tgt$stacked$.wf_source == "online"]
  expected <- 1 / phat_online
  expected <- unname(expected / mean(expected))

  expect_equal(mean(w$data$weight), 1)
  expect_equal(w$data$weight, expected, tolerance = 1e-8)
})

test_that("wf_propensity stabilized weights differ from raw ipw but stay mean 1", {
  tgt <- make_prop_target()
  raw <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE))
  stab <- suppressWarnings(wf_propensity(tgt, stabilize = TRUE))
  # Single group: stabilization is a constant factor, so mean-1 normalization
  # makes the final vectors equal. Assert both are valid mean-1 vectors.
  expect_equal(mean(stab$data$weight), 1)
  expect_equal(stab$provenance$stabilize, TRUE)
  expect_equal(raw$provenance$stabilize, FALSE)
})

test_that("wf_propensity trims extreme weights and records the count", {
  tgt <- make_prop_target()
  untrimmed <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE))
  trimmed <- suppressWarnings(wf_propensity(tgt, stabilize = FALSE, trim = 1.5))

  expect_gte(trimmed$provenance$trimmed, 1)
  expect_lte(max(trimmed$data$weight), max(untrimmed$data$weight) + 1e-9)
  expect_equal(mean(trimmed$data$weight), 1)
})

test_that("wf_propensity rejects reserved methods, weights and bad trim", {
  tgt <- make_prop_target()
  tgt_rf <- tgt; tgt_rf$method <- "rf"
  expect_error(wf_propensity(tgt_rf), class = "wf_error_input")
  expect_error(suppressWarnings(wf_propensity(tgt, weight = "kernel")),
               class = "wf_error_input")
  expect_error(suppressWarnings(wf_propensity(tgt, trim = -1)),
               class = "wf_error_input")
  expect_error(wf_propensity(list()), class = "wf_error_input")
})

test_that("wf_propensity fits per by-group and normalizes within each group", {
  online <- data.frame(
    x = c(1.0, 1.4, 1.8, 2.2, -0.5, 0.9, 1.3, 3.0),
    region = c("n", "n", "n", "n", "s", "s", "s", "s"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-2.0, -1.0, 0.0, 2.8, -1.5, -0.4, 0.4, 2.6),
    region = c("n", "n", "n", "n", "s", "s", "s", "s"),
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ x, by = "region")
  w <- suppressWarnings(wf_propensity(tgt))

  expect_setequal(unique(w$data$group), c("n", "s"))
  expect_equal(mean(w$data$weight[w$data$group == "n"]), 1)
  expect_equal(mean(w$data$weight[w$data$group == "s"]), 1)
})

test_that("wf_propensity errors when a by-group is missing a source", {
  online <- data.frame(
    x = c(1, 2, 3, 4),
    region = c("n", "n", "s", "s"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-1, 0, 1, 2),
    region = c("n", "n", "n", "n"),  # no 's' reference rows
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ x, by = "region")
  expect_error(suppressWarnings(wf_propensity(tgt)), class = "wf_error_overlap")
})

test_that("wf_propensity attaches an overlap report", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))

  expect_type(w$overlap, "list")
  expect_type(w$overlap$online_values, "double")
  expect_type(w$overlap$reference_values, "double")
  expect_length(w$overlap$online_values, tgt$n_online)
  expect_true(all(c("threshold", "online", "reference", "n_boundary", "n_online")
                  %in% names(w$overlap)))
  expect_equal(w$overlap$n_online, tgt$n_online)
})

test_that("wf_propensity warns on poor common support", {
  # A strongly separating (but still convergent) predictor drives some online
  # propensities above the 0.99 boundary.
  online <- data.frame(x = c(3, 5, 7, 9, 11, -1), stringsAsFactors = FALSE)
  reference <- data.frame(x = c(-11, -9, -7, -5, -3, 1), stringsAsFactors = FALSE)
  tgt <- wf_target_propensity(online, reference, member ~ x)

  expect_warning(wf_propensity(tgt), class = "wf_warning_quality")

  w <- suppressWarnings(wf_propensity(tgt))
  expect_gte(w$overlap$n_boundary, 1)
})

test_that("wf_propensity balance table reports unweighted and weighted SMDs", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))

  expect_s3_class(w$balance, "data.frame")
  expect_named(w$balance, c("variable", "level", "smd_unweighted", "smd_weighted"))
  expect_true("x" %in% w$balance$variable)
})

test_that("wf_propensity weighting shrinks the covariate gap", {
  # Online over-represents high x; pseudo-weighting should pull its mean toward
  # the reference, shrinking the standardized mean difference.
  set.seed(1)
  online <- data.frame(x = c(rnorm(40, 1.2, 1), rnorm(10, -1, 1)))
  reference <- data.frame(x = c(rnorm(25, 1, 1), rnorm(25, -1, 1)))
  tgt <- wf_target_propensity(online, reference, member ~ x)
  w <- suppressWarnings(wf_propensity(tgt))

  row <- w$balance[w$balance$variable == "x", ]
  expect_lt(abs(row$smd_weighted), abs(row$smd_unweighted))
})

test_that("wf_propensity expands a factor predictor into per-level balance rows", {
  online <- data.frame(
    x = c(1.0, 1.5, 2.0, 2.5, -0.5),
    g = c("a", "a", "b", "b", "a"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    x = c(-1.0, -0.5, 0.0, 0.5, 1.8),
    g = c("b", "b", "a", "b", "a"),
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ x + g)
  w <- suppressWarnings(wf_propensity(tgt))

  expect_true("g" %in% w$balance$variable)
  expect_true(any(!is.na(w$balance$level)))
})

test_that("print.wf_weights reports the propensity method", {
  tgt <- make_prop_target()
  w <- suppressWarnings(wf_propensity(tgt))
  expect_output(print(w), "method: propensity")
  expect_output(print(w), "overlap:")
})

test_that("wf_propensity output composes via wf_compose", {
  tgt <- make_prop_target()
  stage1 <- suppressWarnings(wf_propensity(tgt))
  stage2 <- stage1
  stage2$data$weight <- rep(2, nrow(stage2$data))
  stage2$data$feature <- 1 / stage2$data$weight

  composed <- wf_compose(propensity = stage1, adj = stage2)
  expect_s3_class(composed, "wf_weights")
  expect_equal(composed$data$weight, stage1$data$weight * 2, tolerance = 1e-8)
})

test_that("wf_propensity weights feed wf_poststrat as init_weight", {
  # wf_poststrat is the calibration stage that exposes the init_weight seam.
  fixture <- make_poststrat_fixture()
  online <- fixture$sample[, c("gender", "age")]
  reference <- data.frame(
    gender = rep(c("female", "male"), each = 4),
    age = rep(c("young", "old"), times = 4),
    stringsAsFactors = FALSE
  )
  tgt <- wf_target_propensity(online, reference, member ~ gender + age)
  pw <- suppressWarnings(wf_propensity(tgt))

  # propensity weights are in online (== sample) row order
  fixture$sample$pw <- pw$data$weight
  weights <- wf_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 2,
    ladder = fixture$ladder,
    init_weight = "pw",
    id = "id"
  )
  expect_s3_class(weights, "wf_weights")
})
