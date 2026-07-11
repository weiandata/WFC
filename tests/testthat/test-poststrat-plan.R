test_that("poststrat planner requires a joint target", {
  fixture <- make_weightflow_fixture()
  ladder <- wf_collapse_ladder(fixture$dims)

  expect_error(
    wf_plan_poststrat(fixture$sample, fixture$target, min_cell = 2, ladder = ladder),
    class = "wf_error_schema"
  )
})

test_that("poststrat planner resolves sparse cells using the ladder", {
  fixture <- make_poststrat_fixture()

  plan <- wf_plan_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 2,
    ladder = fixture$ladder,
    granularity = "adaptive"
  )

  expect_s3_class(plan, "wf_poststrat_plan")
  expect_equal(nrow(plan$plan), 4)
  expect_true(all(c("group", "gender", "age", "pop", "n_sample", "ladder_level", "resolved_cell", "orphan") %in% names(plan$plan)))
  expect_true(any(plan$plan$ladder_level == 1))
  expect_equal(plan$diagnostics$n_cells_raw, 4)
  expect_equal(plan$diagnostics$n_orphan, 0)
})

test_that("poststrat planner flags unsupported cells when requested", {
  fixture <- make_poststrat_fixture()
  fixture$sample <- fixture$sample[fixture$sample$gender == "female", ]

  plan <- wf_plan_poststrat(
    fixture$sample,
    fixture$target,
    min_cell = 1,
    ladder = fixture$ladder,
    empty_cell = "flag"
  )

  expect_true(any(plan$plan$orphan))
  expect_gt(plan$diagnostics$pop_orphan, 0)
})
