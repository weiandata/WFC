make_sparse_safe_workflow_fixture <- function(with_outcomes = FALSE) {
  data <- data.frame(
    id = paste0("r", seq_len(12)),
    province = rep(c("A", "B"), each = 6),
    age = c(rep("young", 5), "old", "young", rep("old", 5)),
    base = rep(1, 12),
    stringsAsFactors = FALSE
  )
  design <- wf_prepare_design(
    data,
    id = "id",
    calibration = c("province", "age"),
    base_weight = "base"
  )
  dims <- wf_dims(age = c("young", "old"))
  population <- data.frame(
    province = rep(c("A", "B"), each = 2),
    age = rep(c("young", "old"), 2),
    count = c(60, 40, 30, 70),
    stringsAsFactors = FALSE
  )
  target <- wf_target_population(
    population,
    key_map = c(age = "age"),
    count = "count",
    dims = dims,
    by = "province",
    by_key = "province",
    keep_joint = TRUE
  )
  target <- .wf_verified_target(
    target,
    evidence = list(demo_only = FALSE, data_checksum = strrep("a", 64)),
    source_type = "population"
  )
  ladder <- wf_collapse_ladder(
    dims,
    level1 = list(age = c(young = "all", old = "all"))
  )
  analysis <- data.frame(
    id = data$id,
    outcome = rep(c(0, 1), 6),
    stringsAsFactors = FALSE
  )

  list(
    design = design,
    target = target,
    dims = dims,
    ladder = ladder,
    analysis = if (with_outcomes) analysis else NULL
  )
}

test_that("support merging is deterministic and conserves design totals", {
  f <- make_sparse_safe_workflow_fixture()

  a <- wf_plan_cells(
    f$design,
    f$target,
    f$dims,
    min_cell = 5,
    ladder = f$ladder
  )
  b <- wf_plan_cells(
    f$design,
    f$target,
    f$dims,
    min_cell = 5,
    ladder = f$ladder
  )

  expect_s3_class(a, "wf_cell_merge_plan")
  expect_identical(a$identity, b$identity)
  expect_equal(sum(a$cells_before$n), sum(a$cells_after$n))
  expect_equal(
    sum(a$cells_before$base_weight),
    sum(a$cells_after$base_weight)
  )
  expect_true(all(a$map$boundary_before == a$map$boundary_after))
  expect_lte(a$projected_max_weight_ratio, 4)
})

test_that("study outcomes cannot alter a merge plan", {
  f <- make_sparse_safe_workflow_fixture(with_outcomes = TRUE)

  p1 <- wf_plan_cells(f$design, f$target, f$dims, ladder = f$ladder)
  f$analysis$outcome <- rev(f$analysis$outcome)
  p2 <- wf_plan_cells(f$design, f$target, f$dims, ladder = f$ladder)

  expect_identical(p1$identity, p2$identity)
})

test_that("stored cell maps apply without recomputing a plan", {
  f <- make_sparse_safe_workflow_fixture()
  plan <- wf_plan_cells(f$design, f$target, f$dims, ladder = f$ladder)

  applied <- .wf_apply_cell_plan(f$design, f$target, plan)

  expect_s3_class(applied$design, "wf_design_data")
  expect_s3_class(applied$target, "wf_verified_target")
  expect_identical(unique(applied$design$data$age), "all")
  expect_identical(names(applied$target$groups$A$margins$age), "all")
  expect_identical(unique(applied$target$joint$A$age), "all")
})

test_that("declared category order provides a deterministic adjacency fallback", {
  f <- make_sparse_safe_workflow_fixture()

  plan <- wf_plan_cells(f$design, f$target, f$dims, min_cell = 5)

  expect_s3_class(plan, "wf_cell_merge_plan")
  expect_true(all(plan$reasons$reason == "declared_order_adjacency"))
  expect_equal(nrow(plan$cells_after), 2)
})

test_that("infeasible declared partitions never widen safety limits", {
  dims <- wf_dims(age = "only")
  design <- wf_prepare_design(
    data.frame(id = "r1", age = "only", stringsAsFactors = FALSE),
    id = "id",
    calibration = "age"
  )
  target <- wf_target_population(
    data.frame(age = "only", count = 10, stringsAsFactors = FALSE),
    key_map = c(age = "age"),
    count = "count",
    dims = dims
  )
  target <- .wf_verified_target(
    target,
    evidence = list(demo_only = FALSE, data_checksum = strrep("b", 64)),
    source_type = "population"
  )

  expect_error(
    wf_plan_cells(design, target, dims, min_cell = 5),
    class = "wf_error_feasibility"
  )
})

test_that("changed inputs cannot reuse a stored cell plan", {
  f <- make_sparse_safe_workflow_fixture()
  plan <- wf_plan_cells(f$design, f$target, f$dims, ladder = f$ladder)
  f$design$data$age[1] <- "old"

  expect_error(
    .wf_apply_cell_plan(f$design, f$target, plan),
    class = "wf_error_safety"
  )
})
