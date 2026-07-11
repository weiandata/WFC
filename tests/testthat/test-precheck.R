test_that("precheck reports unknown sample categories", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$gender[1] <- "other"

  pc <- wf_precheck(sample, fixture$target, id = "id")

  expect_false(pc$ok)
  expect_true("cat_unknown_in_sample" %in% pc$issues$check)
})

test_that("precheck reports infeasible positive target cells", {
  fixture <- make_weightflow_fixture()
  sample <- subset(fixture$sample, !(province == "B" & gender == "male"))

  pc <- wf_precheck(sample, fixture$target, id = "id", na = "drop")

  expect_false(pc$ok)
  expect_true("cat_infeasible" %in% pc$issues$check)
})

test_that("precheck reports duplicate ids", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$id[2] <- sample$id[1]

  pc <- wf_precheck(sample, fixture$target, id = "id")

  expect_false(pc$ok)
  expect_true("dup_id" %in% pc$issues$check)
})

test_that("precheck reports overloaded missing dimensions", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$gender[1] <- NA
  sample$age[1] <- NA

  pc <- wf_precheck(sample, fixture$target, id = "id", max_na_dims = 1)

  expect_false(pc$ok)
  expect_true("na_overload" %in% pc$issues$check)
})

test_that("precheck returns a structured schema failure before deeper checks", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$age <- NULL

  pc <- wf_precheck(sample, fixture$target, id = "id")

  expect_s3_class(pc, "wf_precheck")
  expect_false(pc$ok)
  expect_identical(pc$issues$check, "schema_missing_var")
  expect_match(pc$issues$detail, "age")
})

test_that("precheck reports unmatched and missing group keys", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$province[1] <- "C"
  sample$province[2] <- NA

  pc <- wf_precheck(sample, fixture$target, id = "id")

  expect_false(pc$ok)
  expect_true("group_unmatched" %in% pc$issues$check)
  expect_true("na_group" %in% pc$issues$check)
})

test_that("precheck distinguishes missing-value policies", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$age[1] <- NA

  fractional <- wf_precheck(sample, fixture$target, id = "id", na = "fractional")
  strict <- wf_precheck(sample, fixture$target, id = "id", na = "error")

  expect_true(fractional$ok)
  expect_true(any(
    fractional$issues$check == "na_load" &
      fractional$issues$severity == "note"
  ))
  expect_false(strict$ok)
  expect_true(any(
    strict$issues$check == "na_load" &
      strict$issues$severity == "error"
  ))
})

test_that("precheck records thin-support and extreme-ratio quality warnings", {
  fixture <- make_weightflow_fixture()

  pc <- wf_precheck(
    fixture$sample,
    fixture$target,
    id = "id",
    thin_min = 5,
    risk_ratio = 1
  )

  expect_true(pc$ok)
  expect_true("support_thin" %in% pc$issues$check)
  expect_true("risk_extreme_ratio" %in% pc$issues$check)
  expect_true(all(pc$issues$severity != "error"))
})

test_that("precheck print covers clean and blocked summaries", {
  fixture <- make_weightflow_fixture()
  clean <- wf_precheck(
    fixture$sample,
    fixture$target,
    id = "id",
    thin_min = 1,
    risk_ratio = 100
  )
  expect_output(print(clean), "no issues found")

  blocked_sample <- fixture$sample
  blocked_sample$gender[1] <- "other"
  blocked <- wf_precheck(blocked_sample, fixture$target, id = "id")
  expect_output(print(blocked), "BLOCKED")
  expect_output(print(blocked), "Categories in sample")
})
