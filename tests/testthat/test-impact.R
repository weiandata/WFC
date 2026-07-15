test_that("impact compares estimates without changing locked weights", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  w <- make_locked_safe_weights(f)
  before <- w

  x <- wf_assess_impact(w, f$analysis, "id", c("score", "approved"))

  expect_s3_class(x, "wf_impact")
  expect_true(all(
    c("outcome", "level", "unweighted", "weighted", "difference") %in%
      names(x$summary)
  ))
  expect_true(all(c("kish_ess", "se") %in% names(x$summary)))
  expect_identical(w, before)
  expect_identical(x$weight_identity, w$identity)
})

test_that("categorical impact uses declared factor levels", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  f$analysis$binary <- factor(
    rep(c("no", "yes"), length.out = nrow(f$analysis)),
    levels = c("no", "yes")
  )
  f$analysis$region <- factor(
    rep(c("north", "south", "west"), length.out = nrow(f$analysis)),
    levels = c("north", "south", "west")
  )
  w <- make_locked_safe_weights(f)

  x <- wf_assess_impact(w, f$analysis, "id", c("binary", "region"))

  expect_identical(x$summary$level[x$summary$outcome == "binary"], "yes")
  expect_identical(
    x$summary$level[x$summary$outcome == "region"],
    c("north", "south", "west")
  )
})

test_that("impact rejects ambiguous or structured outcome columns", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  f$analysis$when <- as.Date("2026-01-01") + seq_len(nrow(f$analysis))
  f$analysis$items <- I(rep(list(1:2), nrow(f$analysis)))
  w <- make_locked_safe_weights(f)

  expect_error(
    wf_assess_impact(w, f$analysis, "id", "when"),
    class = "wf_error_safety"
  )
  expect_error(
    wf_assess_impact(w, f$analysis, "id", "items"),
    class = "wf_error_safety"
  )
})

test_that("changed outcomes alter impact but never locked weights", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  w <- make_locked_safe_weights(f)
  before <- w
  first <- wf_assess_impact(w, f$analysis, "id", "score")
  f$analysis$score <- rev(f$analysis$score)

  second <- wf_assess_impact(w, f$analysis, "id", "score")

  expect_false(identical(first$summary, second$summary))
  expect_identical(first$weight_identity, second$weight_identity)
  expect_identical(w, before)
})
