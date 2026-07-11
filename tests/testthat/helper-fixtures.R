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
