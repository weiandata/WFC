test_that("wf_rake init_weight = NULL reproduces the default result exactly", {
  fixture <- make_weightflow_fixture()
  a <- wf_rake(fixture$sample, fixture$target, id = "id")
  b <- wf_rake(fixture$sample, fixture$target, id = "id", init_weight = NULL)
  expect_equal(a$data$weight, b$data$weight)
})

test_that("wf_rake honors non-uniform init weights while matching margins", {
  fixture <- make_weightflow_fixture()
  s <- fixture$sample
  # Vary init WITHIN margin categories (young females only), so it is not
  # absorbed by the marginal gender/age calibration and actually shifts the
  # within-cell association.
  s$bw <- ifelse(s$gender == "female" & s$age == "young", 3, 1)

  uniform <- wf_rake(s, fixture$target, id = "id")
  weighted <- wf_rake(s, fixture$target, id = "id", init_weight = "bw")

  # init weights change the within-solution distribution
  expect_false(isTRUE(all.equal(uniform$data$weight, weighted$data$weight)))

  # but achieved gender totals still match (raking still hits its margins)
  female_uni <- sum(uniform$data$weight[s$gender == "female"])
  female_wtd <- sum(weighted$data$weight[s$gender == "female"])
  expect_equal(female_uni, female_wtd, tolerance = 1e-6)
})

test_that("wf_rake errors when init_weight column is missing", {
  fixture <- make_weightflow_fixture()
  expect_error(
    wf_rake(fixture$sample, fixture$target, id = "id", init_weight = "nope"),
    class = "wf_error_schema"
  )
})

test_that("wf_rake rejects invalid initial weights", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$base_weight <- 1
  sample$base_weight[1] <- -1

  expect_error(
    wf_rake(sample, fixture$target, id = "id", init_weight = "base_weight"),
    class = "wf_error_input"
  )

  sample$base_weight[1] <- NA_real_
  expect_error(
    wf_rake(sample, fixture$target, id = "id", init_weight = "base_weight"),
    class = "wf_error_input"
  )
})

test_that("wf_rake applies explicit missing-value policies", {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$age[1] <- NA

  expect_error(
    wf_rake(sample, fixture$target, id = "id", na = "error"),
    class = "wf_error_feasibility"
  )

  expect_warning(
    dropped <- wf_rake(sample, fixture$target, id = "id", na = "drop"),
    class = "wf_warning_data"
  )
  expect_equal(nrow(dropped$data), nrow(sample) - 1)

  fractional <- wf_rake(sample, fixture$target, id = "id", na = "fractional")
  expect_equal(nrow(fractional$data), nrow(sample))
  expect_true(all(fractional$data$weight > 0))
})
