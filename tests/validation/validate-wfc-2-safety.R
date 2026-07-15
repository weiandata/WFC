set.seed(20260715)

if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("Validation requires the 'pkgload' package.")
}
pkgload::load_all(".", quiet = TRUE)

results <- data.frame(
  scenario = character(),
  expected_code = character(),
  observed_code = character(),
  safety_error = logical(),
  engine_calls_before_refusal = integer(),
  engine_calls_after_refusal = integer(),
  passed = logical(),
  detail = character(),
  stringsAsFactors = FALSE
)

engine_calls <- 0L
engine_names <- c(
  ".wf_rake_engine",
  ".wf_poststrat_engine",
  ".wf_calibrate_engine",
  ".wf_auto_trim_engine",
  ".wf_autoweigh_engine"
)
for (engine in engine_names) {
  trace(
    engine,
    tracer = quote(assign(
      "engine_calls",
      get("engine_calls", envir = .GlobalEnv) + 1L,
      envir = .GlobalEnv
    )),
    print = FALSE,
    where = asNamespace("WFC")
  )
}
on.exit({
  for (engine in engine_names) {
    untrace(engine, where = asNamespace("WFC"))
  }
}, add = TRUE)

capture_refusal <- function(scenario, expected_code, expression) {
  expression <- substitute(expression)
  before <- engine_calls
  condition <- tryCatch(
    eval(expression, envir = parent.frame()),
    error = identity
  )
  after <- engine_calls
  safety_error <- inherits(condition, "wf_error_safety")
  observed_code <- if (safety_error) condition$data$code else NA_character_
  passed <- safety_error && identical(observed_code, expected_code) &&
    identical(before, after)
  detail <- if (inherits(condition, "condition")) {
    conditionMessage(condition)
  } else {
    "No error was raised."
  }
  results <<- rbind(
    results,
    data.frame(
      scenario = scenario,
      expected_code = expected_code,
      observed_code = observed_code,
      safety_error = safety_error,
      engine_calls_before_refusal = before,
      engine_calls_after_refusal = after,
      passed = passed,
      detail = detail,
      stringsAsFactors = FALSE
    )
  )
  invisible(condition)
}

write_population <- function(population, label,
                             selected_before_outcomes = TRUE,
                             demo_only = FALSE) {
  directory <- tempfile(paste0("wfc-2-adversarial-", label, "-"))
  dir.create(directory)
  data_file <- file.path(directory, "population.csv")
  source_file <- paste0(data_file, ".source.dcf")
  utils::write.csv(population, data_file, row.names = FALSE)
  source <- c(
    publisher = "WFC controlled validation fixture",
    dataset_title = paste("Synthetic adversarial target", label),
    citation = "Synthetic validation fixture; not a production authority",
    reference_period = "2026-validation",
    population_scope = "Synthetic validation population",
    retrieved_at = "2026-07-15",
    license = "CC0-1.0",
    checksum_algorithm = "sha256",
    checksum = WFC:::.wf_sha256_file(data_file),
    transformation = "Deterministic synthetic validation construction",
    selected_before_outcomes = tolower(as.character(selected_before_outcomes)),
    demo_only = tolower(as.character(demo_only))
  )
  writeLines(sprintf("%s: %s", names(source), source), source_file)
  list(data_file = data_file, source_file = source_file)
}

dims <- wf_dims(sex = c("F", "M"), age = c("18-34", "35+"))
design_data <- data.frame(
  id = sprintf("r%02d", 1:16),
  sex = rep(c("F", "M"), 8),
  age = rep(c("18-34", "18-34", "35+", "35+"), 4),
  base_weight = 1,
  stringsAsFactors = FALSE
)
population <- data.frame(
  sex = c("F", "M", "F", "M"),
  age = c("18-34", "18-34", "35+", "35+"),
  count = rep(10, 4),
  stringsAsFactors = FALSE
)
source <- write_population(population, "authoritative")
design <- wf_prepare_design(
  design_data,
  id = "id",
  calibration = c("sex", "age"),
  base_weight = "base_weight"
)
target <- wf_import_target(
  source$data_file,
  source$source_file,
  dims,
  key_map = c(sex = "sex", age = "age"),
  count = "count"
)
plan <- wf_plan_weights(design, target, dims)
approval <- wf_approve_plan(plan, "Synthetic reviewer", "test-only reviewer")

# A runtime list of hand-written margins cannot create a pipeline target.
capture_refusal(
  "manual_margins",
  "manual_pipeline_unsupported",
  wf_pipeline(
    target = list(
      mode = "manual",
      margins = list(sex = c(F = 20, M = 20))
    ),
    stages = list(calibrate = list(method = "raking"))
  )
)

# An in-memory pass-rate table is only an ordinary target, regardless of its
# label. It cannot cross the verified public weighting boundary.
outcome_dims <- wf_dims(result = c("pass", "fail"))
pass_rate_target <- wf_target_population(
  data.frame(result = c("pass", "fail"), count = c(80, 20)),
  key_map = c(result = "result"),
  count = "count",
  dims = outcome_dims
)
capture_refusal(
  "pass_rate_target",
  "verified_weighting_inputs_required",
  wf_rake(design, pass_rate_target)
)

# Inline desired means are refused before entropy balancing starts.
capture_refusal(
  "outcome_mean",
  "inline_moments_unsupported",
  wf_calibrate(
    design,
    target,
    method = "ebal",
    moments = c(satisfaction = 0.8)
  )
)

# A desired outcome interval encoded as an ordinary target is also unverified.
outcome_interval_target <- wf_target_population(
  data.frame(result = c("inside", "outside"), count = c(90, 10)),
  key_map = c(result = "result"),
  count = "count",
  dims = wf_dims(result = c("inside", "outside"))
)
capture_refusal(
  "outcome_interval",
  "verified_weighting_inputs_required",
  wf_calibrate(design, outcome_interval_target, method = "raking")
)

# Even a structurally valid target made in memory lacks external evidence.
unverified_target <- wf_target_population(
  population,
  key_map = c(sex = "sex", age = "age"),
  count = "count",
  dims = dims
)
capture_refusal(
  "unverified_target",
  "verified_weighting_inputs_required",
  wf_rake(design, unverified_target)
)

# Demo evidence cannot be imported with the production default.
demo_source <- write_population(population, "demo", demo_only = TRUE)
capture_refusal(
  "demo_target",
  "demo_target_in_production",
  wf_import_target(
    demo_source$data_file,
    demo_source$source_file,
    dims,
    key_map = c(sex = "sex", age = "age"),
    count = "count"
  )
)

# Evidence that admits selection after outcomes is rejected at import.
late_source <- write_population(
  population,
  "selected-after-outcomes",
  selected_before_outcomes = FALSE
)
capture_refusal(
  "target_selected_after_outcomes",
  "target_selected_after_outcomes",
  wf_import_target(
    late_source$data_file,
    late_source$source_file,
    dims,
    key_map = c(sex = "sex", age = "age"),
    count = "count"
  )
)

# Approval for an earlier plan does not authorize a changed plan.
changed_plan <- wf_plan_weights(
  design,
  target,
  dims,
  bounds = c(0.4, 2.5)
)
capture_refusal(
  "stale_approval",
  "plan_approval_mismatch",
  wf_execute_plan(changed_plan, approval, design, target)
)

# Changing one design value invalidates the design identity recorded by plan.
changed_design <- design
changed_design$data$sex[[1]] <- "M"
capture_refusal(
  "changed_design",
  "execution_design_mismatch",
  wf_execute_plan(plan, approval, changed_design, target)
)

# AI agents cannot attest their own approval.
capture_refusal(
  "agent_approval",
  "human_approval_required",
  wf_approve_plan(
    plan,
    approver = "Automated agent",
    role = "assistant",
    actor_type = "agent"
  )
)

# A raw data frame supplied to a public engine wrapper is rejected before the
# internal raking engine is invoked.
capture_refusal(
  "raw_public_engine_call",
  "verified_weighting_inputs_required",
  wf_rake(design$data, target)
)

runtime_margins_absent <- !"margins" %in% names(formals(wf_run))
results <- rbind(
  results,
  data.frame(
    scenario = "runtime_margins_argument_removed",
    expected_code = "argument_removed",
    observed_code = if (runtime_margins_absent) "argument_removed" else NA_character_,
    safety_error = NA,
    engine_calls_before_refusal = engine_calls,
    engine_calls_after_refusal = engine_calls,
    passed = runtime_margins_absent,
    detail = "wf_run() has no margins formal; R rejects that argument.",
    stringsAsFactors = FALSE
  )
)

print(results, row.names = FALSE)
cat("\nSession information:\n")
print(utils::sessionInfo())

if (engine_calls != 0L) {
  stop(sprintf("A weighting engine ran %d time(s) during refusal checks.", engine_calls))
}
if (!all(results$passed)) {
  failed <- results$scenario[!results$passed]
  stop("WFC 2.0 adversarial validation failed: ", paste(failed, collapse = ", "))
}
cat(sprintf("\nAll %d adversarial checks passed before engine execution.\n", nrow(results)))
