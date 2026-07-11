test_that("wf_rake is deterministic and invariant to row order", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample

  first <- wf_rake(sample, fixture$target, id = "id", tol = 1e-10)
  second <- wf_rake(sample, fixture$target, id = "id", tol = 1e-10)

  set.seed(901)
  shuffled <- sample[sample(seq_len(nrow(sample))), , drop = FALSE]
  reordered <- wf_rake(shuffled, fixture$target, id = "id", tol = 1e-10)

  first_weight <- stats::setNames(first$data$weight, first$data$id)
  second_weight <- stats::setNames(second$data$weight, second$data$id)
  reordered_weight <- stats::setNames(reordered$data$weight, reordered$data$id)

  expect_identical(second_weight[names(first_weight)], first_weight)
  expect_equal(
    reordered_weight[names(first_weight)],
    first_weight,
    tolerance = 1e-10
  )
})

test_that("wf_rake is invariant to calibration dimension order", {
  fixture <- make_weightflow_fixture()
  reversed_dims <- wf_dims(
    age = c("young", "old"),
    gender = c("female", "male")
  )
  reversed_target <- wf_target_population(
    fixture$pop,
    key_map = c(age = "age", gender = "gender"),
    count = "count",
    dims = reversed_dims,
    by = "province"
  )

  original <- wf_rake(
    fixture$sample,
    fixture$target,
    id = "id",
    tol = 1e-10
  )
  reversed <- wf_rake(
    fixture$sample,
    reversed_target,
    id = "id",
    tol = 1e-10
  )

  original_weight <- stats::setNames(original$data$weight, original$data$id)
  reversed_weight <- stats::setNames(reversed$data$weight, reversed$data$id)

  expect_equal(
    reversed_weight[names(original_weight)],
    original_weight,
    tolerance = 1e-7
  )
})
