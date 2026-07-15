make_attrition_panel <- function() {
  data.frame(
    id = paste0("p", 1:12),
    region = rep(c("A", "B"), each = 6),
    retained = c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,
                 TRUE, TRUE, FALSE, TRUE, FALSE, FALSE),
    age = c(25, 35, 45, 55, 65, 75, 24, 34, 44, 54, 64, 74),
    sex = rep(c("female", "male"), 6),
    stringsAsFactors = FALSE
  )
}

test_that("wf_attrition returns retained-unit weights and balance diagnostics", {
  panel <- make_attrition_panel()

  attrition <- suppressWarnings(wf_attrition(
    panel,
    retained = "retained",
    formula = ~ age + sex,
    id = "id",
    by = "region",
    trim = 3
  ))

  expect_s3_class(attrition, "wf_attrition_weights")
  expect_s3_class(attrition, "wf_weights")
  expect_true("wf_attrition" %in% getNamespaceExports("WFC"))
  expect_equal(nrow(attrition$data), sum(panel$retained))
  expect_true(all(attrition$data$id %in% panel$id[panel$retained]))
  expect_true(all(attrition$data$weight > 0))
  group_mean <- tapply(attrition$data$weight, attrition$data$group, mean)
  expect_equal(as.numeric(group_mean), c(1, 1), tolerance = 1e-8)
  expect_equal(names(group_mean), c("A", "B"))
  expect_true(all(c(
    "group", "variable", "smd_unweighted", "smd_weighted"
  ) %in% names(attrition$balance)))
  expect_true(all(c("attrition_balance", "attrition_retention") %in%
    names(wf_report(attrition)$sections)))
  expect_output(print(attrition), "wf_attrition_weights", fixed = TRUE)
})

test_that("wf_attrition validates retention model inputs", {
  panel <- make_attrition_panel()

  expect_error(
    wf_attrition(panel, retained = "missing", formula = ~ age, id = "id"),
    class = "wf_error_schema"
  )
  expect_error(
    wf_attrition(panel, retained = "retained", formula = ~ missing, id = "id"),
    class = "wf_error_schema"
  )

  bad <- panel
  bad$age[[1]] <- NA
  expect_error(
    wf_attrition(bad, retained = "retained", formula = ~ age, id = "id"),
    class = "wf_error_input"
  )

  one_source <- panel
  one_source$retained[one_source$region == "A"] <- TRUE
  expect_error(
    wf_attrition(
      one_source,
      retained = "retained",
      formula = ~ age,
      id = "id",
      by = "region"
    ),
    class = "wf_error_overlap"
  )
})

test_that("wf_attrition composes with later weighting stages", {
  panel <- make_attrition_panel()
  attrition <- suppressWarnings(wf_attrition(
    panel,
    retained = "retained",
    formula = ~ age + sex,
    id = "id"
  ))
  retained <- panel[panel$retained, , drop = FALSE]
  stage2 <- attrition
  stage2$data$weight <- rep(2, nrow(stage2$data))
  stage2$data$feature <- 1 / stage2$data$weight
  stage2$provenance$method <- "constant_adjustment"

  composed <- wf_compose(attrition = attrition, adjustment = stage2)

  expect_s3_class(composed, "wf_weights")
  expect_equal(nrow(composed$data), nrow(retained))
  expect_true(all(composed$data$weight > 0))
})

test_that("wf_influence ranks high-impact units and adds margin shares", {
  fixture <- make_weightflow_fixture()
  weights <- .wf_rake_engine(
    fixture$sample,
    fixture$target,
    id = "id",
    tol = 1e-8
  )
  weights$data$weight[weights$data$id == "r01"] <-
    weights$data$weight[weights$data$id == "r01"] * 5

  influence <- wf_influence(
    weights,
    target = fixture$target,
    sample = fixture$sample,
    id = "id",
    top = 3
  )

  expect_s3_class(influence, "wf_influence")
  expect_true("wf_influence" %in% getNamespaceExports("WFC"))
  expect_equal(influence$top, 3)
  expect_equal(influence$table$id[[1]], "r01")
  expect_true(all(c(
    "ratio_to_mean", "deff_share", "deff_loo",
    "deff_drop_if_removed", "max_margin_share"
  ) %in% names(influence$table)))
  expect_true(is.finite(influence$table$deff_loo[[1]]))
  expect_true(is.finite(influence$table$max_margin_share[[1]]))
  expect_output(print(influence), "wf_influence", fixed = TRUE)
})

test_that("wf_influence validates IDs and top count", {
  fixture <- make_weightflow_fixture()
  weights <- .wf_rake_engine(fixture$sample, fixture$target, id = "id")

  expect_error(wf_influence(list()), class = "wf_error_input")
  expect_error(wf_influence(weights, top = 0), class = "wf_error_input")

  dup <- weights
  dup$data$id[[2]] <- dup$data$id[[1]]
  expect_error(wf_influence(dup), class = "wf_error_schema")

  expect_error(
    wf_influence(weights, target = fixture$target, sample = fixture$sample),
    class = "wf_error_input"
  )
})
