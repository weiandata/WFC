make_auto_trim_fixture <- function() {
  fixture <- make_weightflow_fixture()
  fixture$sample$base_weight <- 1
  fixture$sample$base_weight[1] <- 50
  fixture
}

test_that("wf_auto_trim recommends no trimming when the baseline meets criteria", {
  fixture <- make_auto_trim_fixture()

  out <- wf_auto_trim(
    fixture$sample,
    fixture$target,
    id = "id",
    caps = c(2, 4),
    max_deff = 10,
    max_residual = 1,
    init_weight = "base_weight"
  )

  expect_s3_class(out, "wf_auto_trim")
  expect_identical(out$recommended_cap, Inf)
  expect_equal(out$frontier$cap, c(2, 4, Inf))
  expect_true(all(c(
    "feasible", "worst_deff", "worst_residual", "warning_count",
    "error_class", "error_message"
  ) %in% names(out$frontier)))
})

test_that("wf_auto_trim selects the loosest finite cap meeting both criteria", {
  fixture <- make_auto_trim_fixture()

  out <- wf_auto_trim(
    fixture$sample,
    fixture$target,
    id = "id",
    caps = c(2, 3, 4),
    max_deff = 2.1,
    max_residual = 0.04,
    init_weight = "base_weight",
    tol = 1e-8
  )

  expect_equal(out$recommended_cap, 3)
  expect_true(out$frontier$meets_criteria[out$frontier$cap == 3])
  expect_false(out$frontier$meets_criteria[out$frontier$cap == 4])
  expect_false(out$frontier$meets_criteria[is.infinite(out$frontier$cap)])
})

test_that("wf_auto_trim returns NA when no candidate meets the criteria", {
  fixture <- make_auto_trim_fixture()

  out <- wf_auto_trim(
    fixture$sample,
    fixture$target,
    id = "id",
    caps = c(2, 3),
    max_deff = 1,
    max_residual = 0,
    init_weight = "base_weight"
  )

  expect_true(is.na(out$recommended_cap))
  expect_false(any(out$frontier$meets_criteria))
})

test_that("wf_auto_trim records candidate failures without aborting the sweep", {
  fixture <- make_auto_trim_fixture()

  out <- wf_auto_trim(
    fixture$sample,
    fixture$target,
    id = "id",
    caps = c(0.5, 2),
    max_deff = 10,
    max_residual = 1,
    init_weight = "base_weight"
  )

  failed <- out$frontier[out$frontier$cap == 0.5, ]
  expect_false(failed$feasible)
  expect_match(failed$error_class, "wf_error_feasibility")
  expect_true(nzchar(failed$error_message))
  expect_true(out$frontier$feasible[out$frontier$cap == 2])
})

test_that("wf_auto_trim validates its controls and owns the trim argument", {
  fixture <- make_weightflow_fixture()

  expect_error(
    wf_auto_trim(fixture$sample, fixture$target, caps = c(2, NA)),
    class = "wf_error_input"
  )
  expect_error(
    wf_auto_trim(fixture$sample, fixture$target, caps = c(2, 2)),
    class = "wf_error_input"
  )
  expect_error(
    wf_auto_trim(fixture$sample, fixture$target, lo = 0),
    class = "wf_error_input"
  )
  expect_error(
    wf_auto_trim(fixture$sample, fixture$target, max_deff = 0),
    class = "wf_error_input"
  )
  expect_error(
    wf_auto_trim(fixture$sample, fixture$target, trim = c(0.1, 4)),
    class = "wf_error_input"
  )
})

test_that("wf_auto_trim prints its recommendation and frontier", {
  fixture <- make_weightflow_fixture()
  out <- wf_auto_trim(
    fixture$sample,
    fixture$target,
    caps = c(2, 4),
    max_deff = 10,
    max_residual = 1
  )

  expect_output(print(out), "recommended cap")
  expect_output(print(out), "worst_deff")
})
