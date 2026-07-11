test_that("population target can retain joint cells without changing margins", {
  fixture <- make_weightflow_fixture()

  target <- wf_target_population(
    pop = fixture$pop,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = fixture$dims,
    by = "province",
    keep_joint = TRUE
  )

  expect_s3_class(target, "wf_target")
  expect_named(target$joint, c("A", "B"))
  expect_equal(names(target$joint$A), c("gender", "age", "pop"))
  expect_equal(sum(target$joint$A$pop), target$groups$A$total)
  expect_equal(sum(target$joint$B$pop), target$groups$B$total)
  expect_equal(
    unname(tapply(target$joint$A$pop, target$joint$A$gender, sum)["female"]),
    unname(target$groups$A$margins$gender["female"])
  )
})

test_that("population target omits joint cells by default", {
  fixture <- make_weightflow_fixture()

  target <- wf_target_population(
    pop = fixture$pop,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = fixture$dims,
    by = "province"
  )

  expect_null(target$joint)
})

test_that("joint cells follow target scaling", {
  fixture <- make_weightflow_fixture()

  target <- wf_target_population(
    pop = fixture$pop,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = fixture$dims,
    by = "province",
    scale = "custom",
    totals = c(A = 20, B = 30),
    keep_joint = TRUE
  )

  expect_equal(sum(target$joint$A$pop), 20)
  expect_equal(sum(target$joint$B$pop), 30)
  expect_equal(target$groups$A$total, 20)
  expect_equal(target$groups$B$total, 30)
})
