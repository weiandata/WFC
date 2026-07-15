set.seed(20260715)

if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("Validation requires the 'pkgload' package.")
}
pkgload::load_all(".", quiet = TRUE)

results <- data.frame(
  scenario = character(),
  check = character(),
  passed = logical(),
  detail = character(),
  stringsAsFactors = FALSE
)

record_check <- function(scenario, check, passed, detail = "") {
  results <<- rbind(
    results,
    data.frame(
      scenario = scenario,
      check = check,
      passed = isTRUE(passed),
      detail = as.character(detail),
      stringsAsFactors = FALSE
    )
  )
  invisible(passed)
}

write_verified_population <- function(population, label) {
  directory <- tempfile(paste0("wfc-validation-", label, "-"))
  dir.create(directory)
  data_file <- file.path(directory, "population.csv")
  source_file <- paste0(data_file, ".source.dcf")
  utils::write.csv(population, data_file, row.names = FALSE)
  source <- c(
    publisher = "WFC controlled validation fixture",
    dataset_title = paste("Synthetic validation population", label),
    citation = "Synthetic validation fixture; not a production authority",
    reference_period = "2026-validation",
    population_scope = "Synthetic validation population",
    retrieved_at = "2026-07-15",
    license = "CC0-1.0",
    checksum_algorithm = "sha256",
    checksum = WFC:::.wf_sha256_file(data_file),
    transformation = "Deterministic synthetic validation construction",
    selected_before_outcomes = "true",
    demo_only = "false"
  )
  writeLines(sprintf("%s: %s", names(source), source), source_file)
  list(data_file = data_file, source_file = source_file)
}

make_rows <- function(counts) {
  cells <- data.frame(
    sex = c("F", "M", "F", "M"),
    age = c("18-34", "18-34", "35+", "35+"),
    n = counts,
    stringsAsFactors = FALSE
  )
  rows <- cells[rep(seq_len(nrow(cells)), cells$n), c("sex", "age")]
  row.names(rows) <- NULL
  rows$id <- sprintf("r%03d", seq_len(nrow(rows)))
  rows$base_weight <- 1
  rows[c("id", "sex", "age", "base_weight")]
}

dims <- wf_dims(sex = c("F", "M"), age = c("18-34", "35+"))
population <- data.frame(
  sex = c("F", "M", "F", "M"),
  age = c("18-34", "18-34", "35+", "35+"),
  count = rep(10, 4),
  stringsAsFactors = FALSE
)
source <- write_verified_population(population, "balanced")
target <- wf_import_target(
  source$data_file,
  source$source_file,
  dims,
  key_map = c(sex = "sex", age = "age"),
  count = "count"
)

# Scenario 1: supported undercoverage and deterministic locked weights.
undercoverage_data <- make_rows(c(14, 10, 9, 7))
undercoverage_design <- wf_prepare_design(
  undercoverage_data,
  id = "id",
  calibration = c("sex", "age"),
  base_weight = "base_weight"
)
cells_a <- wf_plan_cells(
  undercoverage_design,
  target,
  dims,
  min_cell = 5,
  max_weight_ratio = 4
)
cells_b <- wf_plan_cells(
  undercoverage_design,
  target,
  dims,
  min_cell = 5,
  max_weight_ratio = 4
)
plan_a <- wf_plan_weights(
  undercoverage_design,
  target,
  dims,
  bounds = c(0.3, 3),
  min_cell = 5,
  cell_plan = cells_a
)
plan_b <- wf_plan_weights(
  undercoverage_design,
  target,
  dims,
  bounds = c(0.3, 3),
  min_cell = 5,
  cell_plan = cells_b
)
approval_a <- wf_approve_plan(
  plan_a,
  "Synthetic validation fixture",
  "test-only reviewer"
)
approval_b <- wf_approve_plan(
  plan_b,
  "Synthetic validation fixture",
  "test-only reviewer"
)
weights_a <- wf_execute_plan(
  plan_a,
  approval_a,
  undercoverage_design,
  target
)
weights_b <- wf_execute_plan(
  plan_b,
  approval_b,
  undercoverage_design,
  target
)
aligned_b <- weights_b$data$weight[
  match(weights_a$data$id, weights_b$data$id)
]
ratio_to_mean <- weights_a$data$weight / mean(weights_a$data$weight)

record_check(
  "undercoverage",
  "deterministic_cell_plan",
  identical(cells_a$identity, cells_b$identity),
  cells_a$identity
)
record_check(
  "undercoverage",
  "deterministic_weight_plan",
  identical(plan_a$identity, plan_b$identity),
  plan_a$identity
)
record_check(
  "undercoverage",
  "deterministic_weights",
  isTRUE(all.equal(weights_a$data$weight, aligned_b, tolerance = 1e-10)),
  sprintf("max_abs_diff=%.3g", max(abs(weights_a$data$weight - aligned_b)))
)
record_check(
  "undercoverage",
  "positive_weights",
  all(is.finite(weights_a$data$weight) & weights_a$data$weight > 0),
  sprintf("range=[%.6g, %.6g]", min(weights_a$data$weight), max(weights_a$data$weight))
)
record_check(
  "undercoverage",
  "bounded_relative_to_mean",
  min(ratio_to_mean) >= 0.3 - 1e-8 && max(ratio_to_mean) <= 3 + 1e-8,
  sprintf("ratio_range=[%.6g, %.6g]", min(ratio_to_mean), max(ratio_to_mean))
)
record_check(
  "undercoverage",
  "target_total_conserved",
  abs(sum(weights_a$data$weight) - 40) < 1e-8,
  sprintf("weighted_total=%.12g", sum(weights_a$data$weight))
)

# Outcomes are separate and cannot change plans or locked weights.
analysis <- data.frame(
  id = undercoverage_data$id,
  outcome = rnorm(nrow(undercoverage_data)),
  stringsAsFactors = FALSE
)
impact_a <- wf_assess_impact(weights_a, analysis, "id", "outcome")
analysis$outcome <- rev(analysis$outcome)
impact_b <- wf_assess_impact(weights_a, analysis, "id", "outcome")
record_check(
  "outcome_isolation",
  "locked_identity_unchanged",
  identical(impact_a$weight_identity, impact_b$weight_identity) &&
    identical(impact_a$weight_identity, weights_a$identity),
  weights_a$identity
)
record_check(
  "outcome_isolation",
  "impact_changes_without_reweighting",
  !identical(impact_a$summary, impact_b$summary),
  "outcome order changed after locking"
)

# Scenario 2: a target-positive empty age category is merged only through the
# explicit ladder and conserves sample count and base-weight total.
sparse_data <- data.frame(
  id = sprintf("s%02d", 1:12),
  sex = rep(c("F", "M"), each = 6),
  age = "18-34",
  base_weight = 1,
  stringsAsFactors = FALSE
)
sparse_design <- wf_prepare_design(
  sparse_data,
  id = "id",
  calibration = c("sex", "age"),
  base_weight = "base_weight"
)
sparse_ladder <- wf_collapse_ladder(
  dims,
  merge_age = list(age = c("18-34" = "all", "35+" = "all"))
)
sparse_plan <- wf_plan_cells(
  sparse_design,
  target,
  dims,
  min_cell = 5,
  max_weight_ratio = 4,
  ladder = sparse_ladder
)
record_check(
  "sparse_empty_cells",
  "sample_count_conserved",
  sum(sparse_plan$cells_before$n) == sum(sparse_plan$cells_after$n),
  sprintf("n=%d", sum(sparse_plan$cells_after$n))
)
record_check(
  "sparse_empty_cells",
  "base_weight_conserved",
  abs(sum(sparse_plan$cells_before$base_weight) -
    sum(sparse_plan$cells_after$base_weight)) < 1e-12,
  sprintf("base_total=%.6g", sum(sparse_plan$cells_after$base_weight))
)
record_check(
  "sparse_empty_cells",
  "no_unresolved_cells",
  nrow(sparse_plan$unresolved_cells) == 0,
  sprintf("affected_share=%.6g", sparse_plan$affected_share)
)

# Scenario 3: target mutation/inconsistent totals invalidate recorded identity.
tampered_target <- target
tampered_target$groups$`_all_`$margins$sex[[1]] <-
  tampered_target$groups$`_all_`$margins$sex[[1]] + 1
tamper_error <- tryCatch(
  wf_plan_weights(undercoverage_design, tampered_target, dims),
  error = identity
)
record_check(
  "inconsistent_totals",
  "tampered_target_blocked",
  inherits(tamper_error, "wf_error_safety"),
  if (inherits(tamper_error, "condition")) conditionMessage(tamper_error) else "no error"
)

# Scenario 4: extreme base weights require declared category merging and remain
# bounded after exact approved execution.
extreme_data <- undercoverage_data
extreme_data$base_weight[[1]] <- 50
extreme_design <- wf_prepare_design(
  extreme_data,
  id = "id",
  calibration = c("sex", "age"),
  base_weight = "base_weight"
)
extreme_ladder <- wf_collapse_ladder(
  dims,
  merge_age = list(age = c("18-34" = "all", "35+" = "all")),
  merge_sex = list(sex = c("F" = "all", "M" = "all"))
)
extreme_cells <- wf_plan_cells(
  extreme_design,
  target,
  dims,
  min_cell = 5,
  max_weight_ratio = 4,
  ladder = extreme_ladder
)
extreme_plan <- wf_plan_weights(
  extreme_design,
  target,
  dims,
  bounds = c(0.3, 3),
  min_cell = 5,
  cell_plan = extreme_cells
)
extreme_approval <- wf_approve_plan(
  extreme_plan,
  "Synthetic validation fixture",
  "test-only reviewer"
)
extreme_weights <- wf_execute_plan(
  extreme_plan,
  extreme_approval,
  extreme_design,
  target
)
extreme_ratio <- extreme_weights$data$weight / mean(extreme_weights$data$weight)
record_check(
  "extreme_base_weights",
  "positive_bounded_weights",
  all(extreme_weights$data$weight > 0) &&
    min(extreme_ratio) >= 0.3 - 1e-8 && max(extreme_ratio) <= 3 + 1e-8,
  sprintf("ratio_range=[%.6g, %.6g]", min(extreme_ratio), max(extreme_ratio))
)
record_check(
  "extreme_base_weights",
  "target_total_conserved",
  abs(sum(extreme_weights$data$weight) - 40) < 1e-8,
  sprintf("weighted_total=%.12g", sum(extreme_weights$data$weight))
)

# Optional external reference comparison. CI installs survey and sets
# WFC_REQUIRE_SURVEY=true, making absence a validation failure there.
survey_available <- requireNamespace("survey", quietly = TRUE)
if (identical(tolower(Sys.getenv("WFC_REQUIRE_SURVEY")), "true") &&
    !survey_available) {
  record_check(
    "survey_reference",
    "survey_available",
    FALSE,
    "WFC_REQUIRE_SURVEY=true but package 'survey' is unavailable"
  )
} else if (survey_available) {
  survey_design <- as_svydesign(
    weights_a,
    undercoverage_data,
    id = "id"
  )
  survey_sex <- survey::svytable(~sex, survey_design)
  survey_age <- survey::svytable(~age, survey_design)
  expected_sex <- target$groups$`_all_`$margins$sex[names(survey_sex)]
  expected_age <- target$groups$`_all_`$margins$age[names(survey_age)]
  max_difference <- max(
    abs(as.numeric(survey_sex) - as.numeric(expected_sex)),
    abs(as.numeric(survey_age) - as.numeric(expected_age))
  )
  record_check(
    "survey_reference",
    "raking_margins_match_survey",
    max_difference < 1e-6,
    sprintf("max_abs_difference=%.3g", max_difference)
  )
} else {
  record_check(
    "survey_reference",
    "survey_comparison_skipped",
    TRUE,
    "package 'survey' is not installed locally; CI requires it"
  )
}

print(results, row.names = FALSE)
cat("\nSession information:\n")
print(sessionInfo())

if (any(!results$passed)) {
  stop(sprintf("Safe-workflow validation failed %d check(s).", sum(!results$passed)))
}
cat(sprintf("\nAll %d recorded validation checks passed.\n", nrow(results)))
