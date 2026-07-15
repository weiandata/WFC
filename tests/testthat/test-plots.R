open_test_device <- function() {
  path <- tempfile(fileext = ".pdf")
  grDevices::pdf(path)
  path
}

test_plot_language <- function() {
  "en"
}

test_that("plot methods expose explicit language selection", {
  methods <- c(
    "plot.wf_weights",
    "plot.wf_diagnostics",
    "plot.wf_auto_trim",
    "plot.wf_blend_result",
    "plot.wf_propensity_weights"
  )

  for (method in methods) {
    expect_true("lang" %in% names(formals(get(method, envir = asNamespace("WFC")))))
  }
})

make_plot_blend <- function(sensitivity = TRUE) {
  structure(
    list(
      sensitivity = if (sensitivity) data.frame(
        lambda = rep(c(0.3, 0.5, 0.7), 2),
        group = rep(c("A", "__overall__"), each = 3),
        estimate = c(0.4, 0.5, 0.6, 0.45, 0.52, 0.61)
      ) else NULL,
      provenance = list(method = "blend")
    ),
    class = "wf_blend_result"
  )
}

make_plot_propensity <- function() {
  online <- data.frame(x = c(1, 1.4, 1.8, 2.2, 2.6, 3, 3.4, -0.5))
  reference <- data.frame(x = c(-2, -1.6, -1.2, -0.8, -0.4, 0, 0.4, 2.8))
  target <- wf_target_propensity(online, reference, member ~ x)
  suppressWarnings(wf_propensity(target))
}

test_that("plot.wf_weights draws groups and restores graphics parameters", {
  fixture <- make_weightflow_fixture()
  weights <- .wf_rake_engine(fixture$sample, fixture$target, id = "id")
  weights$provenance$trim <- c(0.5, 3)

  path <- open_test_device()
  on.exit({
    grDevices::dev.off()
    unlink(path)
  }, add = TRUE)
  before <- graphics::par("mfrow")
  expect_invisible(plot(weights, max_groups = 1, lang = test_plot_language()))
  expect_identical(graphics::par("mfrow"), before)
  expect_error(plot(weights, max_groups = 0), class = "wf_error_input")
  expect_error(plot(weights, lang = "fr"), class = "wf_error_input")
})

test_that("plot.wf_diagnostics draws deff and ESS panels", {
  fixture <- make_weightflow_fixture()
  weights <- .wf_rake_engine(fixture$sample, fixture$target, id = "id")
  diagnostics <- wf_diagnose(weights, fixture$target)

  path <- open_test_device()
  on.exit({
    grDevices::dev.off()
    unlink(path)
  }, add = TRUE)
  before <- graphics::par("mfrow")
  expect_invisible(plot(diagnostics, lang = test_plot_language()))
  expect_identical(graphics::par("mfrow"), before)
})

test_that("plot.wf_auto_trim draws the two-axis recommendation frontier", {
  auto <- structure(
    list(
      frontier = data.frame(
        cap = c(2, 3, Inf),
        feasible = TRUE,
        worst_deff = c(1.5, 2, 3),
        worst_residual = c(0.05, 0.02, 0),
        meets_criteria = c(TRUE, TRUE, FALSE)
      ),
      recommended_cap = 3,
      criteria = list(max_deff = 2.5, max_residual = 0.05, lo = 0.05)
    ),
    class = "wf_auto_trim"
  )

  path <- open_test_device()
  on.exit({
    grDevices::dev.off()
    unlink(path)
  }, add = TRUE)
  expect_invisible(plot(auto, lang = test_plot_language()))

  auto$frontier$feasible <- FALSE
  expect_error(plot(auto), class = "wf_error_input")
})

test_that("plot.wf_blend_result draws sensitivity and rejects absent sweeps", {
  path <- open_test_device()
  on.exit({
    grDevices::dev.off()
    unlink(path)
  }, add = TRUE)
  expect_invisible(plot(make_plot_blend(), lang = test_plot_language()))
  expect_error(
    plot(make_plot_blend(sensitivity = FALSE)),
    class = "wf_error_input"
  )
})

test_that("plot.wf_propensity_weights draws overlap and balance panels", {
  weights <- make_plot_propensity()

  path <- open_test_device()
  on.exit({
    grDevices::dev.off()
    unlink(path)
  }, add = TRUE)
  before <- graphics::par("mfrow")
  expect_invisible(plot(weights, lang = test_plot_language()))
  expect_identical(graphics::par("mfrow"), before)
})
