test_that("wf_rake agrees with survey::rake on grouped margins", {
  skip_if_not_installed("survey")

  fixture <- make_weightflow_fixture()
  sample <- fixture$sample
  sample$design_weight <- seq(0.75, 1.5, length.out = nrow(sample))

  actual <- wf_rake(
    sample,
    fixture$target,
    id = "id",
    init_weight = "design_weight",
    trim = NULL,
    tol = 1e-10,
    max_iter = 1000
  )

  for (group in names(fixture$target$groups)) {
    group_sample <- sample[sample$province == group, , drop = FALSE]
    group_target <- fixture$target$groups[[group]]
    design <- survey::svydesign(
      ids = ~1,
      weights = ~design_weight,
      data = group_sample
    )
    oracle <- survey::rake(
      design,
      sample.margins = list(~gender, ~age),
      population.margins = list(
        data.frame(
          gender = names(group_target$margins$gender),
          Freq = unname(group_target$margins$gender)
        ),
        data.frame(
          age = names(group_target$margins$age),
          Freq = unname(group_target$margins$age)
        )
      ),
      control = list(
        maxit = 1000,
        epsilon = 1e-10,
        verbose = FALSE
      )
    )

    actual_weight <- actual$data$weight[
      match(group_sample$id, actual$data$id)
    ]
    expect_equal(
      unname(actual_weight),
      unname(stats::weights(oracle)),
      tolerance = 1e-7,
      info = paste("group", group)
    )
  }
})
