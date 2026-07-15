make_design_data <- function() {
  data.frame(
    id = paste0("u", 1:8),
    stratum = c("A", "A", "A", "A", "B", "B", "B", "B"),
    psu = c("a1", "a1", "a2", "a2", "b1", "b1", "b2", "b2"),
    y = c(1, 0, 1, 1, 0, 0, 1, 0),
    stringsAsFactors = FALSE
  )
}

make_weightflow_fixture <- function() {
  sample <- data.frame(
    id = sprintf("r%02d", 1:16),
    province = rep(c("A", "B"), each = 8),
    gender = rep(c("female", "male", "female", "male"), times = 4),
    age = rep(c("young", "young", "old", "old"), times = 4),
    stringsAsFactors = FALSE
  )

  pop <- data.frame(
    province = rep(c("A", "B"), each = 4),
    gender = rep(c("female", "male", "female", "male"), times = 2),
    age = rep(c("young", "young", "old", "old"), times = 2),
    count = c(40, 60, 60, 40, 30, 70, 50, 50),
    stringsAsFactors = FALSE
  )

  dims <- wf_dims(
    gender = c("female", "male"),
    age = c("young", "old")
  )

  target <- wf_target_population(
    pop = pop,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = dims,
    by = "province"
  )

  list(sample = sample, pop = pop, dims = dims, target = target)
}

make_poststrat_fixture <- function() {
  dims <- wf_dims(gender = c("female", "male"), age = c("young", "old"))
  pop <- data.frame(
    province = "A",
    gender = c("female", "male", "female", "male"),
    age = c("young", "young", "old", "old"),
    count = c(50, 50, 50, 50),
    stringsAsFactors = FALSE
  )
  sample <- data.frame(
    id = paste0("r", 1:10),
    province = "A",
    gender = c(rep("female", 5), rep("male", 5)),
    age = c(rep("young", 4), "old", rep("young", 4), "old"),
    stringsAsFactors = FALSE
  )
  target <- wf_target_population(
    pop,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = dims,
    by = "province",
    keep_joint = TRUE
  )
  ladder <- wf_collapse_ladder(
    dims,
    level1 = list(age = c("young" = "all", "old" = "all"))
  )
  list(
    sample = sample,
    pop = pop,
    target = target,
    dims = dims,
    ladder = ladder
  )
}

make_safe_workflow_fixture <- function(with_outcomes = FALSE) {
  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$base_weight <- 1
  design <- wf_prepare_design(
    sample,
    id = "id",
    calibration = c("province", "gender", "age"),
    base_weight = "base_weight"
  )
  target <- wf_target_population(
    fixture$pop,
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    dims = fixture$dims,
    by = "province",
    by_key = "province",
    keep_joint = TRUE
  )
  target <- .wf_verified_target(
    target,
    evidence = list(demo_only = FALSE, data_checksum = strrep("c", 64)),
    source_type = "population"
  )
  analysis <- data.frame(
    id = sample$id,
    score = seq_len(nrow(sample)),
    approved = rep(c(0, 1), length.out = nrow(sample)),
    stringsAsFactors = FALSE
  )

  list(
    design = design,
    target = target,
    dims = fixture$dims,
    analysis = if (with_outcomes) analysis else NULL
  )
}

make_safe_population_files <- function(population) {
  path <- tempfile("wf-safe-population-")
  dir.create(path)
  data_file <- file.path(path, "population.csv")
  source_file <- paste0(data_file, ".source.dcf")
  utils::write.csv(population, data_file, row.names = FALSE)
  source <- c(
    publisher = "Synthetic fixture publisher",
    dataset_title = "Synthetic population fixture",
    citation = "Synthetic test fixture; not an external authority",
    reference_period = "2026",
    population_scope = "Synthetic adults",
    retrieved_at = "2026-07-15",
    license = "CC0-1.0",
    checksum_algorithm = "sha256",
    checksum = .wf_sha256_file(data_file),
    transformation = "No transformation",
    selected_before_outcomes = "true",
    demo_only = "false"
  )
  writeLines(sprintf("%s: %s", names(source), source), source_file)
  list(data_file = data_file, source_file = source_file)
}

make_locked_safe_weights <- function(fixture = make_safe_workflow_fixture()) {
  plan <- wf_plan_weights(fixture$design, fixture$target, fixture$dims)
  approval <- wf_approve_plan(plan, "Test reviewer", "statistician")
  wf_execute_plan(plan, approval, fixture$design, fixture$target)
}
