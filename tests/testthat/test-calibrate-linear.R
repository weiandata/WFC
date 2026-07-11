test_that(".wf_lincal_dist linear gives F(u)=1+u and F'(u)=1", {
  dist <- .wf_lincal_dist("linear", NULL)
  u <- c(-0.5, 0, 0.5, 2)
  expect_equal(dist$F(u), 1 + u)
  expect_equal(dist$Fp(u), rep(1, length(u)))
})

test_that(".wf_lincal_dist logit maps to (L,U) with F(0)=1 and unit slope at 0", {
  L <- 0.3; U <- 3
  dist <- .wf_lincal_dist("logit", c(L, U))
  u <- seq(-10, 10, by = 0.5)
  fu <- dist$F(u)
  expect_true(all(fu > L & fu < U))
  expect_equal(dist$F(0), 1)
  expect_equal(dist$Fp(0), 1)          # slope at 0 matches the linear distance
})

test_that(".wf_lincal_dist logit F' matches a numeric derivative", {
  dist <- .wf_lincal_dist("logit", c(0.5, 4))
  u0 <- 0.7
  numeric <- (dist$F(u0 + 1e-6) - dist$F(u0 - 1e-6)) / (2e-6)
  expect_equal(dist$Fp(u0), numeric, tolerance = 1e-5)
})

test_that(".wf_lincal_build makes an intercept + dropped-reference-level matrix", {
  sub <- data.frame(g = c("a", "a", "b", "b"), stringsAsFactors = FALSE)
  gr <- list(total = 4, margins = list(g = c(a = 3, b = 1)))
  built <- .wf_lincal_build(sub, dvars = "g", gr = gr)

  # intercept column + one column for the retained level "b" (a is the ref)
  expect_equal(ncol(built$X), 2)
  expect_equal(built$X[, 1], rep(1, 4))
  expect_equal(built$X[, 2], c(0, 0, 1, 1))
  expect_equal(built$t, c(4, 1))          # total, then b's margin
})

test_that(".wf_lincal_build stacks multiple dims, dropping one level each", {
  sub <- data.frame(
    g = c("a", "b", "a", "b"),
    h = c("x", "x", "y", "y"),
    stringsAsFactors = FALSE
  )
  gr <- list(total = 4,
             margins = list(g = c(a = 2, b = 2), h = c(x = 2, y = 2)))
  built <- .wf_lincal_build(sub, dvars = c("g", "h"), gr = gr)
  # intercept + (g: drop a, keep b) + (h: drop x, keep y) = 3 columns
  expect_equal(ncol(built$X), 3)
  expect_equal(built$t, c(4, 2, 2))
})

test_that(".wf_lincal_group solves the GREG closed form by hand", {
  # sample a,a,b,b; base 1; total 4; margin a=3,b=1 -> weights 1.5,1.5,0.5,0.5
  X <- cbind(rep(1, 4), c(0, 0, 1, 1))
  t <- c(4, 1)
  d <- rep(1, 4)
  dist <- .wf_lincal_dist("linear", NULL)
  out <- .wf_lincal_group(X, d, t, dist, tol = 1e-10, max_iter = 100,
                          total = 4, g = "_all_")

  expect_true(out$converged)
  expect_equal(out$w, c(1.5, 1.5, 0.5, 0.5))
  expect_equal(out$iterations, 1)          # linear converges in one step
})

test_that(".wf_lincal_group logit keeps ratios within bounds and hits the target", {
  X <- cbind(rep(1, 4), c(0, 0, 1, 1))
  t <- c(4, 1)
  d <- rep(1, 4)
  dist <- .wf_lincal_dist("logit", c(0.3, 3))
  out <- .wf_lincal_group(X, d, t, dist, tol = 1e-10, max_iter = 100,
                          total = 4, g = "_all_")

  expect_true(out$converged)
  expect_true(all(out$ratio > 0.3 & out$ratio < 3))
  # margins: intercept and category-b constraint both met
  expect_equal(sum(out$w), 4, tolerance = 1e-8)
  expect_equal(sum(out$w[3:4]), 1, tolerance = 1e-8)
})

test_that(".wf_lincal_group aborts when bounds are infeasible", {
  # b units need mean 0.5 but a floor of 0.6 makes sum >= 1.2 > 1: infeasible
  X <- cbind(rep(1, 4), c(0, 0, 1, 1))
  t <- c(4, 1)
  d <- rep(1, 4)
  dist <- .wf_lincal_dist("logit", c(0.6, 3))
  expect_error(
    .wf_lincal_group(X, d, t, dist, tol = 1e-10, max_iter = 50,
                     total = 4, g = "_all_"),
    class = "wf_error_feasibility"
  )
})

test_that(".wf_lincalibrate returns a wf_weights that hits every margin", {
  fixture <- make_weightflow_fixture()
  w <- .wf_lincalibrate(fixture$sample, fixture$target, distance = "linear",
                        method = "greg", id = "id")

  expect_s3_class(w, "wf_weights")
  expect_named(w$data, c("id", "group", "weight", "feature"))
  expect_equal(w$provenance$method, "greg")

  # province A female margin is reproduced
  s <- fixture$sample
  a_female <- sum(w$data$weight[s$province == "A" & s$gender == "female"])
  target_af <- fixture$target$groups[["A"]]$margins$gender[["female"]]
  expect_equal(a_female, target_af, tolerance = 1e-6)
})

test_that(".wf_lincalibrate respects init_weight", {
  fixture <- make_weightflow_fixture()
  s <- fixture$sample
  s$bw <- ifelse(s$gender == "female" & s$age == "young", 3, 1)

  uniform <- .wf_lincalibrate(s, fixture$target, distance = "linear",
                              method = "greg", id = "id")
  weighted <- .wf_lincalibrate(s, fixture$target, distance = "linear",
                               method = "greg", id = "id", init_weight = "bw")

  expect_false(isTRUE(all.equal(uniform$data$weight, weighted$data$weight)))
  # margins still reproduced under a non-uniform base
  a_female <- sum(weighted$data$weight[s$province == "A" & s$gender == "female"])
  expect_equal(a_female, fixture$target$groups[["A"]]$margins$gender[["female"]],
               tolerance = 1e-6)
})

test_that(".wf_lincalibrate drops NA rows with a warning and errors on demand", {
  fixture <- make_weightflow_fixture()
  s <- fixture$sample
  s$gender[1] <- NA

  expect_warning(
    .wf_lincalibrate(s, fixture$target, distance = "linear", method = "greg",
                     id = "id", na = "drop", precheck = FALSE),
    class = "wf_warning_data"
  )
  expect_error(
    .wf_lincalibrate(s, fixture$target, distance = "linear", method = "greg",
                     id = "id", na = "error", precheck = FALSE),
    class = "wf_error_schema"
  )
})

test_that("wf_calibrate routes greg and logit to the calibration engine", {
  fixture <- make_weightflow_fixture()
  greg <- wf_calibrate(fixture$sample, fixture$target, method = "greg",
                       id = "id")
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(0.3, 3), id = "id")

  expect_equal(greg$provenance$method, "greg")
  expect_equal(logit$provenance$method, "logit")
  # logit ratios stay within bounds
  expect_true(all(logit$log$ratio_min >= 0.3 - 1e-9))
  expect_true(all(logit$log$ratio_max <= 3 + 1e-9))
})

test_that("wf_calibrate requires valid bounds for logit", {
  fixture <- make_weightflow_fixture()
  expect_error(
    wf_calibrate(fixture$sample, fixture$target, method = "logit", id = "id"),
    class = "wf_error_input"
  )
  expect_error(
    wf_calibrate(fixture$sample, fixture$target, method = "logit",
                 bounds = c(2, 0.5), id = "id"),
    class = "wf_error_input"
  )
})

test_that("wf_calibrate logit with loose bounds approximates raking", {
  fixture <- make_weightflow_fixture()
  raked <- wf_rake(fixture$sample, fixture$target, id = "id")
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(1e-6, 1e6), id = "id")
  m <- match(raked$data$id, logit$data$id)
  expect_equal(logit$data$weight[m], raked$data$weight, tolerance = 1e-4)
})

test_that("wf_calibrate still routes raking and poststrat unchanged", {
  fixture <- make_weightflow_fixture()
  raked <- wf_calibrate(fixture$sample, fixture$target, method = "raking",
                        id = "id")
  expect_equal(raked$provenance$method, "raking")
})

test_that("print.wf_weights reports the calibration distance and bounds", {
  fixture <- make_weightflow_fixture()
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(0.3, 3), id = "id")
  expect_output(print(logit), "method: logit")
  expect_output(print(logit), "bounds")
})

test_that("logit calibration composes and serves as a replicates refit", {
  fixture <- make_weightflow_fixture()
  logit <- wf_calibrate(fixture$sample, fixture$target, method = "logit",
                        bounds = c(0.2, 5), id = "id")

  # composes with a second stage
  stage2 <- logit
  stage2$data$weight <- rep(2, nrow(stage2$data))
  stage2$data$feature <- 1 / stage2$data$weight
  composed <- wf_compose(cal = logit, adj = stage2)
  expect_s3_class(composed, "wf_weights")

  # serves as a wf_replicates refit. Bounded calibration is on the w/d ratio, so
  # the replicate base weights must be on the population scale: carry a design
  # weight (total/n = 200/8 = 25 in this fixture) via base_weight.
  d <- fixture$sample
  d$y <- as.numeric(d$age == "young")
  d$dw <- 25
  refit <- function(data, weights) {
    data$.bw <- weights
    wf_calibrate(data, fixture$target, method = "logit", bounds = c(0.2, 5),
                 init_weight = ".bw", id = "id", precheck = FALSE)
  }
  reps <- wf_replicates(d, refit, method = "jackknife", id = "id",
                        base_weight = "dw")
  out <- wf_variance(reps, function(w, data) sum(w * data$y) / sum(w), d)
  expect_true(is.finite(out$table$se))
})
