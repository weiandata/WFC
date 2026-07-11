test_that("wf_dims validates named dimensions and collapse ladders", {
  expect_s3_class(wf_dims(gender = c("female", "male")), "wf_dims")
  expect_error(wf_dims(c("female", "male")), class = "wf_error_input")
  expect_error(
    wf_dims(gender = NULL, .collapse = list(age = list(step1 = c("1" = "all")))),
    class = "wf_error_input"
  )
})

test_that("population target validates schema and counts", {
  fixture <- make_weightflow_fixture()

  expect_s3_class(fixture$target, "wf_target")
  expect_equal(fixture$target$dims, c("gender", "age"))
  expect_equal(fixture$target$groups$A$total, 200)
  expect_equal(unname(fixture$target$groups$A$margins$gender["female"]), 100)

  expect_error(
    wf_target_population(
      pop = fixture$pop,
      key_map = c(gender = "missing", age = "age"),
      count = "count",
      dims = fixture$dims,
      by = "province"
    ),
    class = "wf_error_schema"
  )

  bad_pop <- fixture$pop
  bad_pop$count[1] <- -1
  expect_error(
    wf_target_population(
      pop = bad_pop,
      key_map = c(gender = "gender", age = "age"),
      count = "count",
      dims = fixture$dims,
      by = "province"
    ),
    class = "wf_error_input"
  )
})

test_that("target invariant rejects non-additive margins", {
  fixture <- make_weightflow_fixture()
  target <- fixture$target
  target$groups$A$margins$gender["female"] <- target$groups$A$margins$gender["female"] + 1

  expect_error(
    WFC:::.wf_validate_target(target),
    class = "wf_error_input"
  )
})

test_that("reference target screens invalid feature values", {
  fixture <- make_weightflow_fixture()
  ref <- fixture$sample
  ref$feature <- rep(0.5, nrow(ref))

  target <- wf_target_reference(ref, feature = "feature", dims = fixture$dims, by = "province")
  expect_s3_class(target, "wf_target")

  ref$feature[1] <- 0
  expect_error(
    wf_target_reference(ref, feature = "feature", dims = fixture$dims, by = "province"),
    class = "wf_error_input"
  )
})
