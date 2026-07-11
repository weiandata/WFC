library(WFC)

make_benchmark_case <- function(groups, rows_per_group, dimensions, seed) {
  set.seed(seed)
  group_names <- sprintf("g%02d", seq_len(groups))
  dim_names <- paste0("d", seq_len(dimensions))
  n <- groups * rows_per_group

  sample_data <- data.frame(
    id = sprintf("u%07d", seq_len(n)),
    group = rep(group_names, each = rows_per_group),
    stringsAsFactors = FALSE
  )
  for (d in dim_names) {
    sample_data[[d]] <- sample(
      c("a", "b"),
      n,
      replace = TRUE,
      prob = c(0.55, 0.45)
    )
  }

  population <- expand.grid(
    c(list(group = group_names), stats::setNames(
      rep(list(c("a", "b")), dimensions),
      dim_names
    )),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  population$count <- 100 +
    20 * rowSums(population[dim_names] == "a") +
    as.integer(factor(population$group))

  dims_args <- stats::setNames(
    rep(list(c("a", "b")), dimensions),
    dim_names
  )
  dims <- do.call(wf_dims, dims_args)
  target <- wf_target_population(
    population,
    key_map = stats::setNames(dim_names, dim_names),
    count = "count",
    dims = dims,
    by = "group"
  )

  list(sample = sample_data, target = target)
}

max_margin_error <- function(weights, target) {
  max(vapply(names(target$groups), function(group) {
    max(vapply(target$dims, function(dimension) {
      achieved <- weights$achieved[[group]][[dimension]]
      expected <- target$groups[[group]]$margins[[dimension]]
      max(abs(achieved - expected) / pmax(abs(expected), 1))
    }, numeric(1)))
  }, numeric(1)))
}

run_case <- function(name, groups, rows_per_group, dimensions, repetitions, seed) {
  case <- make_benchmark_case(groups, rows_per_group, dimensions, seed)
  elapsed <- numeric(repetitions)
  fit <- NULL

  for (i in seq_len(repetitions)) {
    timing <- system.time({
      fit <- wf_rake(
        case$sample,
        case$target,
        id = "id",
        trim = NULL,
        tol = 1e-8
      )
    })
    elapsed[[i]] <- unname(timing[["elapsed"]])
  }

  expected_totals <- vapply(
    case$target$groups,
    function(group) group$total,
    numeric(1)
  )
  realized_totals <- tapply(fit$data$weight, fit$data$group, sum)

  data.frame(
    case = name,
    rows = nrow(case$sample),
    groups = groups,
    dimensions = dimensions,
    repetitions = repetitions,
    median_seconds = stats::median(elapsed),
    max_seconds = max(elapsed),
    max_margin_relative_error = max_margin_error(fit, case$target),
    max_group_total_absolute_error = max(abs(
      realized_totals[names(expected_totals)] - expected_totals
    )),
    stringsAsFactors = FALSE
  )
}

full <- "--full" %in% commandArgs(trailingOnly = TRUE)
results <- list(
  run_case(
    "32 groups x 5,000 rows x 4 dimensions",
    groups = 32,
    rows_per_group = 5000,
    dimensions = 4,
    repetitions = 3,
    seed = 901
  )
)

if (full) {
  results[[length(results) + 1]] <- run_case(
    "1,000,000 rows x 6 dimensions",
    groups = 32,
    rows_per_group = 31250,
    dimensions = 6,
    repetitions = 1,
    seed = 902
  )
}

results <- do.call(rbind, results)
print(results, row.names = FALSE, digits = 6)
cat("\n")
print(sessionInfo())
