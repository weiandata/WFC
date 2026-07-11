make_collapse_fixture <- function() {
  sample <- data.frame(
    id = paste0("r", 1:6),
    province = "A",
    edu = c("low", "mid", "mid", "high", "high", "high"),
    stringsAsFactors = FALSE
  )
  pop <- data.frame(
    province = "A",
    edu = c("low", "mid", "high"),
    count = c(40, 30, 30),
    stringsAsFactors = FALSE
  )
  dims <- wf_dims(
    edu = c("low", "mid", "high"),
    .collapse = list(
      edu = list(step1 = c(low = "low_mid", mid = "low_mid", high = "high"))
    )
  )
  target <- wf_target_population(
    pop,
    key_map = c(edu = "edu"),
    count = "count",
    dims = dims,
    by = "province"
  )
  list(sample = sample, target = target, dims = dims)
}

test_that("suggest collapse creates a reviewable plan from precheck issues", {
  fixture <- make_collapse_fixture()
  sample <- subset(fixture$sample, edu != "low")
  pc <- wf_precheck(sample, fixture$target, id = "id", na = "drop", thin_min = 2)

  plan <- wf_suggest_collapse(pc, fixture$dims)

  expect_s3_class(plan, "wf_collapse_plan")
  expect_true(nrow(plan$actions) >= 1)
  expect_equal(plan$maps[[1]]$dim, "edu")
  expect_equal(plan$maps[[1]]$map[["low"]], "low_mid")
  expect_true(is.data.frame(plan$source_checks))
})

test_that("suggest collapse records unresolved issues without inventing maps", {
  fixture <- make_collapse_fixture()
  fixture$dims$collapse <- list()
  sample <- subset(fixture$sample, edu != "low")
  pc <- wf_precheck(sample, fixture$target, id = "id", na = "drop", thin_min = 2)

  plan <- wf_suggest_collapse(pc, fixture$dims)

  expect_s3_class(plan, "wf_collapse_plan")
  expect_length(plan$maps, 0)
  expect_gt(nrow(plan$unresolved), 0)
})

test_that("apply collapse accepts old list plans and new wf_collapse_plan objects", {
  fixture <- make_collapse_fixture()
  old <- wf_apply_collapse(
    fixture$sample,
    fixture$target,
    list(dim = "edu", map = c(low = "low_mid", mid = "low_mid"))
  )
  expect_true("low_mid" %in% old$sample$edu)
  expect_true("low_mid" %in% names(old$target$groups$A$margins$edu))

  sample <- subset(fixture$sample, edu != "low")
  pc <- wf_precheck(sample, fixture$target, id = "id", na = "drop", thin_min = 2)
  plan <- wf_suggest_collapse(pc, fixture$dims)
  applied <- wf_apply_collapse(sample, fixture$target, plan)

  expect_true("low_mid" %in% applied$sample$edu)
  expect_true("low_mid" %in% names(applied$target$groups$A$margins$edu))
  expect_true(!is.null(applied$target$meta$collapsed))
})

test_that("apply collapse keeps post-stratification joint cells synchronized", {
  fixture <- make_poststrat_fixture()
  total_before <- sum(fixture$target$joint$A$pop)

  applied <- wf_apply_collapse(
    fixture$sample,
    fixture$target,
    list(dim = "age", map = c(young = "all", old = "all"))
  )

  expect_identical(unique(applied$sample$age), "all")
  expect_identical(unique(applied$target$joint$A$age), "all")
  expect_equal(nrow(applied$target$joint$A), 2)
  expect_equal(sum(applied$target$joint$A$pop), total_before)
})
