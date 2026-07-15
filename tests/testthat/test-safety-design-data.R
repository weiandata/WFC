test_that("every design column has an explicit role", {
  d <- data.frame(
    id = c("a", "b"),
    sex = c("F", "M"),
    base = c(1, 2)
  )

  x <- wf_prepare_design(d, "id", "sex", base_weight = "base")

  expect_s3_class(x, "wf_design_data")
  expect_identical(x$roles$calibration, "sex")
  expect_match(x$identity, "^[0-9a-f]{64}$")
})

test_that("unassigned outcome-like columns block", {
  d <- data.frame(
    id = 1:2,
    sex = c("F", "M"),
    outcome = c(1, 0)
  )

  expect_error(
    wf_prepare_design(d, "id", "sex"),
    class = "wf_error_safety"
  )
})
