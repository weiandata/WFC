make_soft_fixture <- function() {
  dims <- wf_dims(segment = c("covered", "missing"))
  margins <- data.frame(
    dimension = c("segment", "segment"),
    category = c("covered", "missing"),
    value = c(90, 10),
    stringsAsFactors = FALSE
  )
  target <- suppressWarnings(wf_target_manual(margins, dims))
  sample <- data.frame(
    id = paste0("s", 1:4),
    segment = "covered",
    stringsAsFactors = FALSE
  )
  list(sample = sample, target = target, dims = dims)
}

make_ebal_fixture <- function() {
  dims <- wf_dims(gender = c("female", "male"))
  margins <- data.frame(
    dimension = c("gender", "gender"),
    category = c("female", "male"),
    value = c(2, 2),
    stringsAsFactors = FALSE
  )
  target <- suppressWarnings(wf_target_manual(margins, dims))
  sample <- data.frame(
    id = paste0("e", 1:4),
    gender = c("female", "female", "male", "male"),
    x = c(0, 1, 0, 1),
    stringsAsFactors = FALSE
  )
  list(sample = sample, target = target, dims = dims)
}

test_that("soft calibration relaxes infeasible margins within declared tolerance", {
  fixture <- make_soft_fixture()

  soft <- wf_calibrate(
    fixture$sample,
    fixture$target,
    method = "soft",
    id = "id",
    tolerance = 0.11
  )

  expect_s3_class(soft, "wf_weights")
  expect_identical(soft$provenance$method, "soft")
  expect_equal(sum(soft$data$weight), 100, tolerance = 1e-8)
  expect_equal(soft$achieved[["_all_"]]$segment[["missing"]], 0)
  expect_true(all(soft$relaxation$within_tolerance))
  expect_true(any(soft$relaxation$dim == "segment" & soft$relaxation$relaxed))
  expect_true("soft_relaxation" %in% names(wf_report(soft)$sections))
  expect_output(print(soft), "soft calibration", fixed = TRUE)
})

test_that("soft calibration refuses relaxation beyond tolerance", {
  fixture <- make_soft_fixture()

  expect_error(
    wf_calibrate(
      fixture$sample,
      fixture$target,
      method = "soft",
      id = "id",
      tolerance = 0.05
    ),
    class = "wf_error_feasibility"
  )
  expect_error(
    wf_calibrate(
      fixture$sample,
      fixture$target,
      method = "soft",
      id = "id",
      tolerance = c(segment = -0.1)
    ),
    class = "wf_error_input"
  )
})

test_that("soft calibration still blocks non-relaxable precheck errors", {
  fixture <- make_soft_fixture()
  bad <- fixture$sample
  bad$segment[[1]] <- "unknown"

  expect_error(
    wf_calibrate(
      bad,
      fixture$target,
      method = "soft",
      id = "id",
      tolerance = 0.2
    ),
    class = "wf_error_feasibility"
  )
})

test_that("entropy balancing hits categorical margins and continuous moments", {
  fixture <- make_ebal_fixture()

  ebal <- suppressWarnings(wf_calibrate(
    fixture$sample,
    fixture$target,
    method = "ebal",
    id = "id",
    moments = c(x = 0.75),
    tol = 1e-10
  ))

  expect_s3_class(ebal, "wf_weights")
  expect_identical(ebal$provenance$method, "ebal")
  expect_identical(ebal$provenance$distance, "entropy")
  expect_equal(sum(ebal$data$weight), 4, tolerance = 1e-8)
  expect_equal(ebal$achieved[["_all_"]]$gender[["male"]], 2, tolerance = 1e-8)
  expect_equal(
    sum(ebal$data$weight * fixture$sample$x) / sum(ebal$data$weight),
    0.75,
    tolerance = 1e-8
  )
  expect_equal(ebal$moments$achieved_mean, 0.75, tolerance = 1e-8)
  expect_true(is.finite(ebal$log$kl_divergence))
  expect_true("entropy_moments" %in% names(wf_report(ebal)$sections))
  expect_output(print(ebal), "entropy balancing", fixed = TRUE)
})

test_that("entropy balancing validates moment declarations", {
  fixture <- make_ebal_fixture()

  expect_error(
    suppressWarnings(wf_calibrate(
      fixture$sample,
      fixture$target,
      method = "ebal",
      id = "id",
      moments = c(missing = 1)
    )),
    class = "wf_error_schema"
  )

  bad <- fixture$sample
  bad$z <- c("a", "b", "a", "b")
  expect_error(
    suppressWarnings(wf_calibrate(
      bad,
      fixture$target,
      method = "ebal",
      id = "id",
      moments = c(z = 1)
    )),
    class = "wf_error_schema"
  )
})

test_that("pipeline calibration stage accepts 0.14 methods", {
  fixture <- make_ebal_fixture()
  spec <- wf_pipeline(
    target = fixture$target,
    stages = list(
      calibrate = list(method = "ebal", id = "id", moments = c(x = 0.75))
    )
  )

  out <- suppressWarnings(wf_run(spec, fixture$sample))

  expect_s3_class(out, "wf_weights")
  expect_identical(out$provenance$method, "ebal")
  expect_identical(out$provenance$pipeline_hash, spec$hash)
})
