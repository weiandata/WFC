test_that("only a matching human-attested approval executes", {
  f <- make_safe_workflow_fixture()
  p <- wf_plan_weights(f$design, f$target, f$dims)

  expect_error(
    wf_approve_plan(p, "agent", "assistant", actor_type = "agent"),
    class = "wf_error_safety"
  )

  a <- wf_approve_plan(p, "Reviewer", "statistician")
  w <- wf_execute_plan(p, a, f$design, f$target)

  expect_s3_class(w, "wf_locked_weights")
  expect_identical(w$plan_identity, p$identity)
  expect_identical(w$approval_identity, a$identity)
  expect_match(w$identity, "^[0-9a-f]{64}$")
})

test_that("stale approvals and changed inputs stop before calibration", {
  f <- make_safe_workflow_fixture()
  p <- wf_plan_weights(f$design, f$target, f$dims)
  a <- wf_approve_plan(p, "Reviewer", "statistician")
  f$design$data$gender[1] <- "male"

  expect_error(
    wf_execute_plan(p, a, f$design, f$target),
    class = "wf_error_safety"
  )
})

test_that("guided and lower-level workflows produce identical results", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$base_weight <- 1
  files <- make_safe_population_files(fixture$pop)

  design <- wf_prepare_design(
    sample,
    id = "id",
    calibration = c("province", "gender", "age"),
    base_weight = "base_weight"
  )
  target <- wf_import_target(
    files$data_file,
    files$source_file,
    fixture$dims,
    c(gender = "gender", age = "age"),
    "count",
    by = "province",
    by_key = "province"
  )
  cells <- wf_plan_cells(design, target, fixture$dims)
  plan <- wf_plan_weights(design, target, fixture$dims, cell_plan = cells)

  guided <- wf_guided_plan(
    sample,
    id = "id",
    calibration = c("province", "gender", "age"),
    dims = fixture$dims,
    target_file = files$data_file,
    source_file = files$source_file,
    source_type = "population",
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    base_weight = "base_weight",
    by = "province",
    by_key = "province"
  )

  expect_identical(guided$plan$identity, plan$identity)
  approval <- wf_approve_plan(plan, "Reviewer", "statistician")
  lower <- wf_execute_plan(plan, approval, design, target)
  higher <- wf_guided_execute(guided, approval)
  lower_weights <- lower$data$weight[match(sample$id, lower$data$id)]
  higher_weights <- higher$data$weight[match(sample$id, higher$data$id)]
  expect_equal(lower_weights, higher_weights)
})

test_that("locked weights attach by ID without changing row order", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  p <- wf_plan_weights(f$design, f$target, f$dims)
  a <- wf_approve_plan(p, "Reviewer", "statistician")
  w <- wf_execute_plan(p, a, f$design, f$target)
  data <- f$analysis[c(4, 1, 3, 2, 5:nrow(f$analysis)), , drop = FALSE]

  attached <- wf_attach_weights(data, w, id = "id")

  expect_identical(attached$id, data$id)
  expect_equal(
    attached$.weight,
    w$data$weight[match(data$id, w$data$id)]
  )
  expect_identical(attr(attached, "wf_locked_weight_identity"), w$identity)
})

test_that("approved logit and poststrat methods dispatch exactly", {
  f <- make_safe_workflow_fixture()
  logit_data <- f$design$data
  logit_data$base_weight <- 25
  logit_design <- wf_prepare_design(
    logit_data,
    id = "id",
    calibration = c("province", "gender", "age"),
    base_weight = "base_weight"
  )
  logit_plan <- wf_plan_weights(
    logit_design,
    f$target,
    f$dims,
    method = "logit"
  )
  logit_approval <- wf_approve_plan(
    logit_plan,
    "Reviewer",
    "statistician"
  )

  logit_weights <- wf_execute_plan(
    logit_plan,
    logit_approval,
    logit_design,
    f$target
  )

  expect_identical(logit_weights$provenance$method, "logit")

  cells <- wf_plan_cells(f$design, f$target, f$dims)
  poststrat_plan <- wf_plan_weights(
    f$design,
    f$target,
    f$dims,
    method = "poststrat",
    cell_plan = cells
  )
  poststrat_approval <- wf_approve_plan(
    poststrat_plan,
    "Reviewer",
    "statistician"
  )

  poststrat_weights <- wf_execute_plan(
    poststrat_plan,
    poststrat_approval,
    f$design,
    f$target
  )

  expect_identical(poststrat_weights$provenance$method, "poststrat")
})
