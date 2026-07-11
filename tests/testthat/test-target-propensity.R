make_prop_frames <- function() {
  online <- data.frame(
    pid = paste0("o", 1:6),
    age = c(20, 25, 30, 35, 40, 45),
    edu = c("hs", "hs", "col", "col", "hs", "col"),
    stringsAsFactors = FALSE
  )
  reference <- data.frame(
    pid = paste0("r", 1:6),
    age = c(22, 33, 44, 55, 60, 28),
    edu = c("col", "col", "hs", "hs", "col", "hs"),
    stringsAsFactors = FALSE
  )
  list(online = online, reference = reference)
}

test_that("wf_target_propensity rejects a one-sided formula", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, ~ age + edu),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity rejects an empty right-hand side", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, member ~ 1),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity errors when a predictor is missing", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, member ~ age + income),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity errors when membership name collides", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online, f$reference, age ~ age + edu),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity errors on empty frames", {
  f <- make_prop_frames()
  expect_error(
    wf_target_propensity(f$online[0, ], f$reference, member ~ age),
    class = "wf_error_input"
  )
})

test_that("wf_target_propensity builds a membership indicator and keeps online order", {
  f <- make_prop_frames()
  tgt <- wf_target_propensity(f$online, f$reference, member ~ age + edu)

  expect_s3_class(tgt, "wf_target_propensity")
  expect_equal(tgt$membership, "member")
  expect_setequal(tgt$predictors, c("age", "edu"))
  # online rows first, in order, all member == 1
  expect_equal(tgt$stacked$member, c(rep(1L, 6), rep(0L, 6)))
  expect_equal(tgt$stacked$.wf_source, c(rep("online", 6), rep("reference", 6)))
  expect_equal(tgt$stacked$age[1:6], f$online$age)
})

test_that("wf_target_propensity uses row order ids by default and the id column when given", {
  f <- make_prop_frames()
  tgt_default <- wf_target_propensity(f$online, f$reference, member ~ age)
  expect_equal(tgt_default$online_ids, as.character(1:6))

  tgt_id <- wf_target_propensity(f$online, f$reference, member ~ age, id = "pid")
  expect_equal(tgt_id$online_ids, f$online$pid)
})

test_that("wf_target_propensity does not fit a model at construction", {
  f <- make_prop_frames()
  tgt <- wf_target_propensity(f$online, f$reference, member ~ age)
  expect_false("model" %in% names(tgt))
})
