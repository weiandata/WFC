test_that(".wf_design resolves strata and clusters", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  expect_equal(des$n, 8)
  expect_setequal(des$strata, c("A", "B"))
  expect_setequal(des$psu[["A"]], c("a1", "a2"))
})

test_that(".wf_design defaults each row to its own PSU and a single stratum", {
  d <- make_design_data()
  des <- .wf_design(d, strata = NULL, clusters = NULL)
  expect_equal(des$strata, "1")
  expect_equal(length(des$psu[["1"]]), 8)
})

test_that(".wf_design rejects clusters that span strata", {
  d <- make_design_data()
  d$psu[5] <- "a1"  # a1 now appears in both stratum A and B
  expect_error(
    .wf_design(d, strata = "stratum", clusters = "psu"),
    class = "wf_error_design"
  )
})

test_that(".wf_design rejects missing columns", {
  d <- make_design_data()
  expect_error(.wf_design(d, strata = "nope", clusters = NULL),
               class = "wf_error_input")
})

test_that(".wf_boot_mult returns an n x R matrix with unit scale/rscales", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_boot_mult(des, R = 50, seed = 1)

  expect_equal(dim(gen$mult), c(8, 50))
  expect_equal(gen$scale, 1 / 50)
  expect_equal(gen$rscales, rep(1, 50))
  expect_true(all(gen$mult >= 0))
})

test_that(".wf_boot_mult multipliers are constant within a PSU", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_boot_mult(des, R = 10, seed = 1)
  # rows 1,2 are PSU a1; rows 3,4 are PSU a2
  expect_equal(gen$mult[1, ], gen$mult[2, ])
  expect_equal(gen$mult[3, ], gen$mult[4, ])
})

test_that(".wf_boot_mult per-stratum multiplier mean is about 1", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_boot_mult(des, R = 4000, seed = 42)
  stratum_A <- colMeans(gen$mult[1:4, ])  # 2 PSUs x 2 units, mean over units per rep
  expect_equal(mean(stratum_A), 1, tolerance = 0.05)
})

test_that(".wf_boot_mult is reproducible with a seed", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  g1 <- .wf_boot_mult(des, R = 20, seed = 7)
  g2 <- .wf_boot_mult(des, R = 20, seed = 7)
  expect_identical(g1$mult, g2$mult)
})

test_that(".wf_jack_mult emits one replicate per PSU with the right rescale", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_jack_mult(des)

  # 2 strata x 2 PSUs = 4 replicates
  expect_equal(ncol(gen$mult), 4)
  expect_equal(gen$scale, 1)
  expect_equal(gen$rscales, rep((2 - 1) / 2, 4))
})

test_that(".wf_jack_mult deletes exactly one PSU and rescales its stratum", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_jack_mult(des)

  # first replicate deletes PSU a1 (rows 1,2): 0 there, 2 for rows 3,4, 1 elsewhere
  col1 <- gen$mult[, 1]
  expect_equal(col1[1:2], c(0, 0))
  expect_equal(col1[3:4], c(2, 2))       # n_h/(n_h-1) = 2
  expect_equal(col1[5:8], rep(1, 4))     # other stratum untouched
})

test_that(".wf_jack_mult warns on a single-PSU stratum and skips it", {
  d <- make_design_data()
  d$stratum[8] <- "C"
  d$psu[8] <- "c1"                       # stratum C has 1 PSU
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  expect_warning(.wf_jack_mult(des), class = "wf_warning_quality")
})

test_that(".wf_hadamard builds an orthogonal +/-1 matrix of order a power of two", {
  H <- .wf_hadamard(3)         # next power of two >= 3 is 4
  expect_equal(dim(H), c(4, 4))
  expect_true(all(H %in% c(-1, 1)))
  expect_equal(t(H) %*% H, diag(4) * 4)
})

test_that(".wf_brr_mult assigns 2/0 within each 2-PSU stratum", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_brr_mult(des)

  expect_equal(gen$scale, 1 / ncol(gen$mult))
  expect_equal(gen$rscales, rep(1, ncol(gen$mult)))
  # rows 1,2 are PSU a1; rows 3,4 are PSU a2 (stratum A)
  for (r in seq_len(ncol(gen$mult))) {
    expect_true(all(gen$mult[1:4, r] %in% c(0, 2)))
    expect_equal(gen$mult[1, r], gen$mult[2, r])   # same PSU, same multiplier
    expect_equal(gen$mult[3, r], gen$mult[4, r])
    expect_equal(gen$mult[1, r] + gen$mult[3, r], 2)  # exactly one PSU selected
  }
})

test_that(".wf_brr_mult supports Fay shrinkage", {
  d <- make_design_data()
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  gen <- .wf_brr_mult(des, rho = 0.3)

  expect_equal(gen$scale, 1 / (ncol(gen$mult) * (1 - 0.3)^2))
  expect_equal(gen$rscales, rep(1, ncol(gen$mult)))
  expect_true(all(gen$mult %in% c(0.3, 1.7)))
  for (r in seq_len(ncol(gen$mult))) {
    expect_equal(gen$mult[1, r] + gen$mult[3, r], 2)
  }
})

test_that(".wf_brr_mult rejects a stratum without exactly 2 PSUs", {
  d <- make_design_data()
  d$psu[4] <- "a3"             # stratum A now has 3 PSUs
  des <- .wf_design(d, strata = "stratum", clusters = "psu")
  expect_error(.wf_brr_mult(des), class = "wf_error_design")
})

# A trivial refit: no calibration, weights = base (so we can verify wiring).
trivial_refit <- function(data, weights) {
  structure(list(
    data = data.frame(id = data$id, group = "all",
                      weight = weights, feature = 1 / weights,
                      stringsAsFactors = FALSE)
  ), class = "wf_weights")
}

test_that("wf_replicates returns aligned base and replicate weights", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap",
                         R = 30, strata = "stratum", clusters = "psu",
                         id = "id", seed = 1)

  expect_s3_class(rep_w, "wf_replicate_weights")
  expect_equal(nrow(rep_w$base), 8)
  expect_equal(rep_w$base$id, d$id)
  expect_equal(dim(rep_w$replicates), c(8, 30))
  expect_equal(rep_w$base$weight, rep(1, 8))   # trivial refit, base = 1
  expect_equal(rep_w$provenance$method, "bootstrap")
  expect_equal(rep_w$provenance$seed, 1)
})

test_that("wf_replicates applies base_weight and perturbs it by the multipliers", {
  d <- make_design_data()
  d$bw <- rep(2, 8)
  rep_w <- wf_replicates(d, trivial_refit, method = "jackknife",
                         strata = "stratum", clusters = "psu",
                         id = "id", base_weight = "bw")
  # jackknife replicate 1 deletes PSU a1: rows 1,2 -> 0, rows 3,4 -> 2*2=4
  expect_equal(rep_w$replicates[1:2, 1], c(0, 0))
  expect_equal(rep_w$replicates[3:4, 1], c(4, 4))
})

test_that("wf_replicates errors when refit returns mismatched ids", {
  d <- make_design_data()
  bad_refit <- function(data, weights) {
    structure(list(
      data = data.frame(id = paste0("x", seq_len(nrow(data))),
                        group = "all", weight = weights,
                        feature = 1 / weights, stringsAsFactors = FALSE)
    ), class = "wf_weights")
  }
  expect_error(
    wf_replicates(d, bad_refit, method = "bootstrap", R = 3,
                  strata = "stratum", clusters = "psu", id = "id"),
    class = "wf_error_input"
  )
})

test_that("wf_replicates validates its inputs", {
  d <- make_design_data()
  expect_error(wf_replicates(d, "notfun", method = "bootstrap", id = "id"),
               class = "wf_error_input")
  expect_error(wf_replicates(d, trivial_refit, method = "bootstrap",
                             R = 0, id = "id"),
               class = "wf_error_input")
  expect_error(wf_replicates(d, trivial_refit, method = "bootstrap",
                             id = "missing"),
               class = "wf_error_input")
  expect_error(wf_replicates(d, trivial_refit, method = "brr",
                             strata = "stratum", clusters = "psu",
                             id = "id", rho = 1),
               class = "wf_error_input")
  expect_error(wf_replicates(d, trivial_refit, method = "bootstrap",
                             id = "id", rho = 0.3),
               class = "wf_error_input")
})

test_that("print.wf_replicate_weights reports method and replicate count", {
  d <- make_design_data()
  rep_w <- wf_replicates(d, trivial_refit, method = "bootstrap", R = 5,
                         strata = "stratum", clusters = "psu", id = "id",
                         seed = 1)
  expect_output(print(rep_w), "wf_replicate_weights")
  expect_output(print(rep_w), "bootstrap")

  fay <- wf_replicates(d, trivial_refit, method = "brr",
                       strata = "stratum", clusters = "psu",
                       id = "id", rho = 0.3)
  expect_equal(fay$rho, 0.3)
  expect_equal(fay$provenance$rho, 0.3)
  expect_output(print(fay), "Fay rho")
})
