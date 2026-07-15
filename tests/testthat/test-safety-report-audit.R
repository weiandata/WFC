test_that("decision and statistician aliases preserve legacy report tables", {
  fixture <- make_weightflow_fixture()
  f <- list(
    weights = .wf_rake_engine(fixture$sample, fixture$target, id = "id"),
    target = fixture$target
  )

  decision <- wf_report(f$weights, f$target, audience = "decision")
  manager <- wf_report(f$weights, f$target, audience = "manager")
  statistician <- wf_report(f$weights, f$target, audience = "statistician")
  analyst <- wf_report(f$weights, f$target, audience = "analyst")

  expect_identical(decision$table, manager$table)
  expect_identical(statistician$table, analyst$table)
  expect_identical(decision$requested_audience, "decision")
  expect_identical(decision$audience, "manager")
})

test_that("safe workflow reports separate decision and statistician detail", {
  workflow <- make_safe_review_workflow()

  decision <- wf_report(workflow, audience = "decision")
  statistician <- wf_report(workflow, audience = "statistician")

  expect_identical(decision$source_type, "safe_workflow")
  expect_true(all(c("status", "method", "affected_share", "next_action") %in%
    names(decision$table)))
  expect_true(all(c("source_evidence", "precheck_issues", "cell_map") %in%
    names(statistician$sections)))
  expect_gt(ncol(statistician$sections$cell_map), 0)
})

test_that("locked and impact reports expose evidence without planning controls", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  locked <- make_locked_safe_weights(f)
  impact <- wf_assess_impact(locked, f$analysis, "id", c("score", "approved"))

  locked_report <- wf_report(locked, audience = "statistician")
  impact_report <- wf_report(impact, audience = "decision")

  expect_identical(locked_report$source_type, "locked_weights")
  expect_true("lock_evidence" %in% names(locked_report$sections))
  expect_identical(impact_report$source_type, "impact")
  expect_true(all(c("outcome", "unweighted", "weighted", "difference") %in%
    names(impact_report$table)))
  expect_false(any(c("bounds", "target", "method") %in%
    names(impact_report$table)))
})

test_that("safe audit v2 carries the complete available identity chain", {
  f <- make_safe_workflow_fixture(with_outcomes = TRUE)
  locked <- make_locked_safe_weights(f)
  impact <- wf_assess_impact(locked, f$analysis, "id", "score")

  locked_payload <- .wf_audit_payload(locked)
  impact_payload <- .wf_audit_payload(impact)

  expect_identical(locked_payload$schema, "wfc_audit_v2")
  expect_identical(
    locked_payload$identities$locked_weight,
    locked$identity
  )
  expect_identical(locked_payload$identities$plan, locked$plan_identity)
  expect_identical(locked_payload$identities$approval, locked$approval_identity)
  expect_identical(impact_payload$identities$impact, impact$identity)
  expect_identical(
    impact_payload$identities$locked_weight,
    impact$weight_identity
  )

  path <- tempfile(fileext = ".json")
  expect_identical(wf_audit_export(impact, path), path)
  expect_match(
    paste(readLines(path, warn = FALSE), collapse = "\n"),
    "\"schema\":\"wfc_audit_v2\"",
    fixed = TRUE
  )
})
