make_ladder_draft_fixture <- function() {
  group <- rep(c("A", "B"), each = 12)
  age <- c(
    "young", rep("middle", 5), rep("old", 6),
    rep("young", 2), rep("middle", 4), rep("old", 6)
  )
  education <- rep("high", 24)
  education[c(1, 13)] <- "low"
  sample <- data.frame(
    id = paste0("u", seq_len(24)),
    region = group,
    age = age,
    education = education,
    stringsAsFactors = FALSE
  )
  dims <- wf_dims(
    age = c("young", "middle", "old"),
    education = c("low", "high")
  )
  margins <- do.call(rbind, lapply(c("A", "B"), function(g) {
    rbind(
      data.frame(
        region = g,
        dimension = "age",
        category = c("young", "middle", "old"),
        value = c(30, 45, 45)
      ),
      data.frame(
        region = g,
        dimension = "education",
        category = c("low", "high"),
        value = c(30, 90)
      )
    )
  }))
  target <- wf_target_manual(
    margins,
    dims,
    by = "region",
    group_col = "region"
  )
  list(sample = sample, dims = dims, target = target)
}

test_that("wf_suggest_ladder drafts adjacent merges from worst-group support", {
  fixture <- make_ladder_draft_fixture()

  draft <- wf_suggest_ladder(
    fixture$sample,
    fixture$target,
    fixture$dims,
    min_cell = 3
  )

  expect_s3_class(draft, "wf_ladder_draft")
  expect_named(draft$levels, c("level1", "level2"))
  expect_identical(names(draft$levels$level1), "age")
  expect_identical(names(draft$levels$level2), "education")
  expect_equal(draft$levels$level1$age[["young"]], "young+middle")
  expect_equal(draft$levels$level1$age[["middle"]], "young+middle")
  expect_false("old" %in% names(draft$levels$level1$age))
  expect_s3_class(draft$ladder, "wf_collapse_ladder")
  expect_equal(draft$ladder$n_levels, 2)
})

test_that("wf_suggest_ladder orders dimensions by affected sample share", {
  fixture <- make_ladder_draft_fixture()
  draft <- wf_suggest_ladder(
    fixture$sample,
    fixture$target,
    fixture$dims,
    min_cell = 3
  )

  expect_lt(draft$affected_share[["age"]], draft$affected_share[["education"]])
  expect_identical(names(draft$affected_share), c("age", "education"))
  expect_equal(draft$support_before$age["young", "A"], 1)
  expect_equal(draft$support_before$age["young", "B"], 2)
})

test_that("wf_suggest_ladder returns a validated no-op draft when support is sufficient", {
  fixture <- make_ladder_draft_fixture()

  draft <- wf_suggest_ladder(
    fixture$sample,
    fixture$target,
    fixture$dims,
    min_cell = 1
  )

  expect_length(draft$levels, 0)
  expect_length(draft$affected_share, 0)
  expect_equal(draft$ladder$n_levels, 0)
})

test_that("wf_suggest_ladder does not mutate inputs", {
  fixture <- make_ladder_draft_fixture()
  sample_before <- fixture$sample
  target_before <- fixture$target
  dims_before <- fixture$dims

  wf_suggest_ladder(
    fixture$sample,
    fixture$target,
    fixture$dims,
    min_cell = 3
  )

  expect_identical(fixture$sample, sample_before)
  expect_identical(fixture$target, target_before)
  expect_identical(fixture$dims, dims_before)
})

test_that("wf_suggest_ladder requires declared order and compatible inputs", {
  fixture <- make_ladder_draft_fixture()
  inferred <- wf_dims(age = NULL, education = c("low", "high"))

  expect_error(
    wf_suggest_ladder(fixture$sample, fixture$target, inferred),
    class = "wf_error_input"
  )
  expect_error(
    wf_suggest_ladder(fixture$sample, fixture$target, fixture$dims, min_cell = 0),
    class = "wf_error_input"
  )

  missing_column <- fixture$sample
  missing_column$age <- NULL
  expect_error(
    wf_suggest_ladder(missing_column, fixture$target, fixture$dims),
    class = "wf_error_schema"
  )

  missing_group <- fixture$sample[fixture$sample$region == "A", ]
  expect_error(
    wf_suggest_ladder(missing_group, fixture$target, fixture$dims),
    class = "wf_error_feasibility"
  )
})

test_that("wf_suggest_ladder prints a review warning and mappings", {
  fixture <- make_ladder_draft_fixture()
  draft <- wf_suggest_ladder(
    fixture$sample,
    fixture$target,
    fixture$dims,
    min_cell = 3
  )

  expect_output(print(draft), "review before use")
  expect_output(print(draft), "young->young\\+middle")
})
