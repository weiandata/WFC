test_that("planning is deterministic and computes no weights", {
  f <- make_safe_workflow_fixture()

  a <- wf_plan_weights(f$design, f$target, f$dims)
  b <- wf_plan_weights(f$design, f$target, f$dims)

  expect_s3_class(a, "wf_weight_plan")
  expect_identical(a$identity, b$identity)
  expect_null(a$weights)
  expect_s3_class(a$precheck, "wf_precheck")
})

test_that("only verified non-demo targets can enter a weight plan", {
  f <- make_safe_workflow_fixture()
  class(f$target) <- "wf_target"

  expect_error(
    wf_plan_weights(f$design, f$target, f$dims),
    class = "wf_error_safety"
  )
})

test_that("a supplied cell plan must match immutable inputs", {
  f <- make_safe_workflow_fixture()
  cells <- wf_plan_cells(
    f$design,
    f$target,
    f$dims,
    min_cell = 1,
    max_weight_ratio = 10
  )

  plan <- wf_plan_weights(
    f$design,
    f$target,
    f$dims,
    min_cell = 1,
    cell_plan = cells
  )

  expect_identical(plan$cell_plan$identity, cells$identity)
  expect_identical(plan$input_identities$design, f$design$identity)
  expect_identical(plan$input_identities$target, f$target$identity)
})

test_that("non-substantive cell-plan timestamps do not change plan identity", {
  f <- make_safe_workflow_fixture()
  cells_a <- wf_plan_cells(
    f$design,
    f$target,
    f$dims,
    min_cell = 1,
    max_weight_ratio = 10
  )
  cells_b <- cells_a
  cells_b$created <- "2099-01-01T00:00:00+0000"

  plan_a <- wf_plan_weights(
    f$design,
    f$target,
    f$dims,
    min_cell = 1,
    cell_plan = cells_a
  )
  plan_b <- wf_plan_weights(
    f$design,
    f$target,
    f$dims,
    min_cell = 1,
    cell_plan = cells_b
  )

  expect_identical(plan_a$identity, plan_b$identity)
})
