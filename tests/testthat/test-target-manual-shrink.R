test_that("manual target constructs canonical margins for one group", {
  dims <- wf_dims(gender = c("female", "male"), age = c("young", "old"))
  margins <- data.frame(
    dimension = c("gender", "gender", "age", "age"),
    category = c("female", "male", "young", "old"),
    value = c(60, 40, 55, 45),
    stringsAsFactors = FALSE
  )

  target <- wf_target_manual(margins, dims)

  expect_s3_class(target, "wf_target")
  expect_equal(target$mode, "manual")
  expect_null(target$by)
  expect_equal(names(target$groups), "_all_")
  expect_equal(target$groups$`_all_`$total, 100)
  expect_equal(target$groups$`_all_`$margins$gender, c(female = 60, male = 40))
  expect_equal(target$groups$`_all_`$margins$age, c(young = 55, old = 45))
})

test_that("manual target constructs grouped targets with explicit totals", {
  dims <- wf_dims(gender = c("female", "male"))
  margins <- data.frame(
    province = c("A", "A", "B", "B"),
    dimension = "gender",
    category = c("female", "male", "female", "male"),
    value = c(60, 40, 30, 70),
    stringsAsFactors = FALSE
  )

  target <- wf_target_manual(
    margins,
    dims,
    by = "province",
    totals = c(A = 100, B = 100)
  )

  expect_equal(target$by, "province")
  expect_equal(names(target$groups), c("A", "B"))
  expect_equal(target$groups$B$margins$gender, c(female = 30, male = 70))
})

test_that("manual target rejects non-additive dimensions", {
  dims <- wf_dims(gender = c("female", "male"), age = c("young", "old"))
  margins <- data.frame(
    dimension = c("gender", "gender", "age", "age"),
    category = c("female", "male", "young", "old"),
    value = c(60, 40, 55, 40),
    stringsAsFactors = FALSE
  )

  expect_error(
    wf_target_manual(margins, dims),
    class = "wf_error_input"
  )
})

test_that("target shrinkage preserves local totals and blends shares", {
  dims <- wf_dims(gender = c("female", "male"))
  local <- wf_target_manual(
    data.frame(
      province = c("A", "A"),
      dimension = "gender",
      category = c("female", "male"),
      value = c(80, 20),
      stringsAsFactors = FALSE
    ),
    dims,
    by = "province"
  )
  reference <- wf_target_manual(
    data.frame(
      dimension = c("gender", "gender"),
      category = c("female", "male"),
      value = c(50, 50),
      stringsAsFactors = FALSE
    ),
    dims
  )

  shrunk <- wf_target_shrink(local, reference, lambda = 0.25)

  expect_s3_class(shrunk, "wf_target")
  expect_equal(shrunk$groups$A$total, 100)
  expect_equal(unname(shrunk$groups$A$margins$gender["female"]), 57.5, tolerance = 1e-8)
  expect_equal(unname(shrunk$groups$A$margins$gender["male"]), 42.5, tolerance = 1e-8)
  expect_true(!is.null(shrunk$meta$shrinkage))
})

test_that("target shrinkage rejects invalid lambda and incompatible categories", {
  dims <- wf_dims(gender = c("female", "male"))
  local <- wf_target_manual(
    data.frame(
      dimension = c("gender", "gender"),
      category = c("female", "male"),
      value = c(80, 20),
      stringsAsFactors = FALSE
    ),
    dims
  )
  bad_ref <- wf_target_manual(
    data.frame(
      dimension = c("gender", "gender"),
      category = c("female", "other"),
      value = c(50, 50),
      stringsAsFactors = FALSE
    ),
    wf_dims(gender = c("female", "other"))
  )

  expect_error(wf_target_shrink(local, local, lambda = 1.5), class = "wf_error_input")
  expect_error(wf_target_shrink(local, bad_ref, lambda = 0.5), class = "wf_error_schema")
})
