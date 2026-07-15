test_that("WFC 2.0 adversarial validation evidence is complete", {
  root <- normalizePath(test_path("..", ".."), mustWork = FALSE)
  script <- file.path(root, "tests", "validation", "validate-wfc-2-safety.R")
  report <- file.path(root, "docs", "validation", "wfc-2.0-safety-validation.md")

  expect_true(file.exists(script))
  skip_if_not(file.exists(report), "validation report is not installed")

  evidence <- paste(
    c(readLines(script, warn = FALSE), readLines(report, warn = FALSE)),
    collapse = "\n"
  )
  required_scenarios <- c(
    "manual_margins",
    "pass_rate_target",
    "outcome_mean",
    "outcome_interval",
    "unverified_target",
    "demo_target",
    "stale_approval",
    "changed_design",
    "agent_approval",
    "raw_public_engine_call"
  )
  required_codes <- c(
    "manual_pipeline_unsupported",
    "inline_moments_unsupported",
    "verified_weighting_inputs_required",
    "demo_target_in_production",
    "plan_approval_mismatch",
    "execution_design_mismatch",
    "human_approval_required"
  )

  expect_true(all(vapply(
    required_scenarios,
    grepl,
    logical(1),
    x = evidence,
    fixed = TRUE
  )))
  expect_true(all(vapply(
    required_codes,
    grepl,
    logical(1),
    x = evidence,
    fixed = TRUE
  )))
  expect_match(evidence, "engine_calls_before_refusal", fixed = TRUE)
  expect_match(evidence, "does not prove source truth", fixed = TRUE)
  expect_match(evidence, "qualified human statistical review", fixed = TRUE)
  release_evidence <- c(
    "WFC 2.0 accountable release approval: **completed**",
    "WFC 2.0 qualified human statistical review: **completed**",
    "Reviewer: Jinyan Zhu",
    "Reviewer qualification: statistical expert",
    "Review completion date: 2026-07-15",
    "Review scope: all WFC 2.0 functionality",
    "Approver: Kunxiang Ma",
    "Approver role: company legal representative",
    "Package release authorized: **yes**"
  )
  expect_true(all(vapply(
    release_evidence,
    grepl,
    logical(1),
    x = evidence,
    fixed = TRUE
  )))
})
