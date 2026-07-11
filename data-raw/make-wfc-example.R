set.seed(20260709)

sample <- data.frame(
  id = sprintf("sim-%03d", 1:80),
  province = rep(c("North", "South"), each = 40),
  gender = rep(c("female", "male"), times = 40),
  age = rep(c("young", "young", "old", "old"), times = 20),
  stringsAsFactors = FALSE
)

population <- data.frame(
  province = rep(c("North", "South"), each = 4),
  gender = rep(c("female", "male", "female", "male"), times = 2),
  age = rep(c("young", "young", "old", "old"), times = 2),
  count = c(120, 100, 80, 100, 90, 110, 100, 100),
  stringsAsFactors = FALSE
)

dims <- wf_dims(
  gender = c("female", "male"),
  age = c("young", "old")
)

wfc_example <- list(
  sample = sample,
  population = population,
  dims = dims
)

save(wfc_example, file = "data/wfc_example.rda", compress = "xz")
