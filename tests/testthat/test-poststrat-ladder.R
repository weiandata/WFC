test_that("collapse ladder validates dimensions and cumulative source categories", {
  dims <- wf_dims(age = c("1", "2", "3", "4", "5"), edu = c("L", "M", "H"))

  ladder <- wf_collapse_ladder(
    dims,
    level1 = list(age = c("4" = "45", "5" = "45")),
    level2 = list(age = c("1" = "123", "2" = "123", "3" = "123", "45" = "45"))
  )

  expect_s3_class(ladder, "wf_collapse_ladder")
  expect_equal(ladder$dims, c("age", "edu"))
  expect_equal(ladder$n_levels, 2)

  mat <- matrix(
    c("4", "L", "5", "H", "2", "M"),
    ncol = 2,
    byrow = TRUE,
    dimnames = list(NULL, c("age", "edu"))
  )
  expect_equal(WFC:::.wf_apply_ladder(mat, ladder, 1)[, "age"], c("45", "45", "2"))
  expect_equal(WFC:::.wf_apply_ladder(mat, ladder, 2)[, "age"], c("45", "45", "123"))
})

test_that("collapse ladder rejects unknown dimensions and typo categories", {
  dims <- wf_dims(age = c("1", "2"), edu = c("L", "H"))

  expect_error(
    wf_collapse_ladder(dims, level1 = list(region = c("A" = "B"))),
    class = "wf_error_input"
  )
  expect_error(
    wf_collapse_ladder(dims, level1 = list(age = c("3" = "2"))),
    class = "wf_error_input"
  )
})

test_that("cell keys split back into dimension columns", {
  mat <- matrix(c("female", "young", "male", "old"), ncol = 2, byrow = TRUE)
  colnames(mat) <- c("gender", "age")

  key <- WFC:::.wf_cell_key(mat, c("gender", "age"))
  out <- WFC:::.wf_split_key(key, c("gender", "age"))

  expect_equal(out$gender, c("female", "male"))
  expect_equal(out$age, c("young", "old"))
})
