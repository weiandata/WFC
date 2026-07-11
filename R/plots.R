#' Merge plot defaults with user arguments.
#'
#' @param defaults Default argument list.
#' @param dots User argument list.
#' @keywords internal
#' @noRd
.wf_plot_args <- function(defaults, dots) {
  utils::modifyList(defaults, dots)
}

#' Plot calibrated weight distributions
#'
#' Draws one histogram per group, including the group mean and recorded raking
#' trim bounds when available.
#'
#' @param x A `wf_weights` object.
#' @param max_groups Maximum number of groups to plot.
#' @param lang Output language.
#' @param ... Additional arguments passed to [graphics::hist()].
#' @return Invisibly returns `x`.
#' @export
plot.wf_weights <- function(x, max_groups = 9, lang = NULL, ...) {
  language <- .wf_lang(lang)
  if (length(max_groups) != 1 || !is.finite(max_groups) || max_groups < 1 ||
      max_groups != as.integer(max_groups)) {
    wf_abort("`max_groups` must be a positive integer.", "wf_error_input")
  }
  if (!is.data.frame(x$data) || nrow(x$data) == 0 ||
      !all(c("group", "weight") %in% names(x$data))) {
    wf_abort("`x` has no plottable weight data.", "wf_error_input")
  }
  groups <- unique(.chr(x$data$group))
  groups <- groups[seq_len(min(length(groups), as.integer(max_groups)))]
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  layout <- if (length(groups) <= 3) {
    c(1, length(groups))
  } else {
    grDevices::n2mfrow(length(groups))
  }
  graphics::par(mfrow = layout)
  dots <- list(...)

  for (group in groups) {
    weight <- x$data$weight[.chr(x$data$group) == group]
    args <- .wf_plot_args(
      list(
        x = weight,
        main = .wf_tr("plot_group_title", group, lang = language),
        xlab = .wf_tr("plot_weight", lang = language),
        col = "grey85",
        border = "white"
      ),
      dots
    )
    do.call(graphics::hist, args)
    graphics::abline(v = mean(weight), lty = 2, lwd = 1.5)
    trim <- x$provenance$trim
    if (is.numeric(trim) && length(trim) == 2 && all(is.finite(trim))) {
      graphics::abline(v = mean(weight) * trim, lty = 3, col = "firebrick")
    }
  }
  invisible(x)
}

#' Plot weight diagnostics
#'
#' Draws design effects and effective-sample-size shares by group.
#'
#' @param x A `wf_diagnostics` object.
#' @param lang Output language.
#' @param ... Additional arguments passed to [graphics::dotchart()].
#' @return Invisibly returns `x`.
#' @export
plot.wf_diagnostics <- function(x, lang = NULL, ...) {
  language <- .wf_lang(lang)
  if (!is.data.frame(x$table) || nrow(x$table) == 0 ||
      !all(c("group", "n", "ess", "deff") %in% names(x$table))) {
    wf_abort("`x` has no plottable diagnostic table.", "wf_error_input")
  }
  table <- x$table[is.finite(x$table$deff) & is.finite(x$table$ess), , drop = FALSE]
  if (nrow(table) == 0) {
    wf_abort("No finite diagnostics are available to plot.", "wf_error_input")
  }
  table <- table[order(table$deff), , drop = FALSE]
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(1, 2))
  dots <- list(...)

  do.call(
    graphics::dotchart,
    .wf_plot_args(
      list(
        x = table$deff,
        labels = table$group,
        xlab = .wf_tr("plot_design_effect", lang = language)
      ),
      dots
    )
  )
  graphics::abline(v = c(3, 10), lty = 3, col = "grey45")

  do.call(
    graphics::dotchart,
    .wf_plot_args(
      list(
        x = table$ess / table$n,
        labels = table$group,
        xlab = .wf_tr("plot_effective_sample_share", lang = language),
        xlim = c(0, 1)
      ),
      dots
    )
  )
  invisible(x)
}

#' Plot an automatic trim frontier
#'
#' Draws the worst design effect and residual margin error for every feasible
#' finite cap.
#'
#' @param x A `wf_auto_trim` object.
#' @param lang Output language.
#' @param ... Additional arguments passed to the initial plot calls.
#' @return Invisibly returns `x`.
#' @export
plot.wf_auto_trim <- function(x, lang = NULL, ...) {
  language <- .wf_lang(lang)
  frontier <- x$frontier[
    x$frontier$feasible & is.finite(x$frontier$cap),
    ,
    drop = FALSE
  ]
  if (nrow(frontier) == 0) {
    wf_abort("No feasible finite trim candidates are available to plot.", "wf_error_input")
  }
  frontier <- frontier[order(frontier$cap), , drop = FALSE]
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(1, 2))
  dots <- list(...)

  do.call(
    graphics::plot,
    .wf_plot_args(
      list(
        x = frontier$cap,
        y = frontier$worst_deff,
        type = "b",
        xlab = .wf_tr("plot_trim_cap", lang = language),
        ylab = .wf_tr("plot_worst_deff", lang = language)
      ),
      dots
    )
  )
  graphics::abline(h = x$criteria$max_deff, lty = 3, col = "grey45")
  if (is.finite(x$recommended_cap)) {
    graphics::abline(v = x$recommended_cap, lty = 2, col = "firebrick")
  }

  do.call(
    graphics::plot,
    .wf_plot_args(
      list(
        x = frontier$cap,
        y = frontier$worst_residual,
        type = "b",
        xlab = .wf_tr("plot_trim_cap", lang = language),
        ylab = .wf_tr("plot_worst_residual", lang = language)
      ),
      dots
    )
  )
  graphics::abline(h = x$criteria$max_residual, lty = 3, col = "grey45")
  if (is.finite(x$recommended_cap)) {
    graphics::abline(v = x$recommended_cap, lty = 2, col = "firebrick")
  }
  invisible(x)
}

#' Plot blend lambda sensitivity
#'
#' @param x A `wf_blend_result` containing sensitivity output.
#' @param lang Output language.
#' @param ... Additional arguments passed to the initial plot.
#' @return Invisibly returns `x`.
#' @export
plot.wf_blend_result <- function(x, lang = NULL, ...) {
  language <- .wf_lang(lang)
  sensitivity <- x$sensitivity
  if (!is.data.frame(sensitivity) || nrow(sensitivity) == 0 ||
      !all(c("lambda", "group", "estimate") %in% names(sensitivity))) {
    wf_abort(
      "No lambda sensitivity is available; create the blend with sensitivity = TRUE.",
      "wf_error_input"
    )
  }
  keep <- is.finite(sensitivity$lambda) & is.finite(sensitivity$estimate)
  sensitivity <- sensitivity[keep, , drop = FALSE]
  if (nrow(sensitivity) == 0) {
    wf_abort("No finite lambda sensitivity values are available.", "wf_error_input")
  }
  groups <- unique(.chr(sensitivity$group))
  colours <- stats::setNames(grDevices::hcl.colors(length(groups), "Dark 3"), groups)
  dots <- list(...)
  do.call(
    graphics::plot,
    .wf_plot_args(
      list(
        x = range(sensitivity$lambda),
        y = range(sensitivity$estimate),
        type = "n",
        xlab = .wf_tr("plot_online_lambda", lang = language),
        ylab = .wf_tr("plot_fused_estimate", lang = language)
      ),
      dots
    )
  )
  for (group in groups) {
    part <- sensitivity[.chr(sensitivity$group) == group, , drop = FALSE]
    part <- part[order(part$lambda), , drop = FALSE]
    graphics::lines(
      part$lambda,
      part$estimate,
      col = colours[[group]],
      lwd = if (group == "__overall__") 3 else 1.5
    )
  }
  if (length(groups) > 1) {
    graphics::legend(
      "topleft",
      legend = groups,
      col = colours[groups],
      lty = 1,
      lwd = ifelse(groups == "__overall__", 3, 1.5),
      bty = "n"
    )
  }
  invisible(x)
}

#' Plot propensity overlap and covariate balance
#'
#' @param x A `wf_propensity_weights` object.
#' @param lang Output language.
#' @param ... Additional arguments passed to the initial plot calls.
#' @return Invisibly returns `x`.
#' @export
plot.wf_propensity_weights <- function(x, lang = NULL, ...) {
  language <- .wf_lang(lang)
  online <- x$overlap$online_values
  reference <- x$overlap$reference_values
  balance <- x$balance
  if (!is.numeric(online) || !is.numeric(reference) ||
      length(online) < 2 || length(reference) < 2) {
    wf_abort("Raw propensity values are unavailable for overlap plotting.", "wf_error_input")
  }
  if (!is.data.frame(balance) || nrow(balance) == 0 ||
      !all(c("variable", "level", "smd_unweighted", "smd_weighted") %in%
           names(balance))) {
    wf_abort("Covariate balance values are unavailable for plotting.", "wf_error_input")
  }
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(1, 2))
  dots <- list(...)

  if (length(unique(online)) > 1 && length(unique(reference)) > 1) {
    density_online <- stats::density(online, from = 0, to = 1)
    density_reference <- stats::density(reference, from = 0, to = 1)
    do.call(
      graphics::plot,
      .wf_plot_args(
        list(
          x = density_online,
          xlim = c(0, 1),
          ylim = c(0, max(density_online$y, density_reference$y)),
          main = .wf_tr("plot_propensity_overlap", lang = language),
          xlab = .wf_tr("plot_online_propensity", lang = language),
          ylab = .wf_tr("plot_density", lang = language),
          col = "#0072B2",
          lwd = 2
        ),
        dots
      )
    )
    graphics::lines(density_reference, col = "#D55E00", lwd = 2)
  } else {
    do.call(
      graphics::plot,
      .wf_plot_args(
        list(
          x = c(0, 1),
          y = c(0, 1),
          type = "n",
          main = .wf_tr("plot_propensity_overlap", lang = language),
          xlab = .wf_tr("plot_online_propensity", lang = language),
          ylab = ""
        ),
        dots
      )
    )
    graphics::rug(online, col = "#0072B2")
    graphics::rug(reference, side = 3, col = "#D55E00")
  }
  graphics::legend(
    "topleft",
    legend = c(
      .wf_tr("plot_online", lang = language),
      .wf_tr("plot_reference", lang = language)
    ),
    col = c("#0072B2", "#D55E00"),
    lty = 1,
    lwd = 2,
    bty = "n"
  )

  labels <- ifelse(
    is.na(balance$level),
    balance$variable,
    paste(balance$variable, balance$level, sep = ":")
  )
  unweighted <- abs(balance$smd_unweighted)
  weighted <- abs(balance$smd_weighted)
  limit <- max(c(unweighted, weighted, 0.1), na.rm = TRUE)
  y <- seq_along(labels)
  do.call(
    graphics::plot,
    .wf_plot_args(
      list(
        x = c(0, limit * 1.05),
        y = range(y),
        type = "n",
        yaxt = "n",
        xlab = .wf_tr("plot_absolute_smd", lang = language),
        ylab = "",
        main = .wf_tr("plot_covariate_balance", lang = language)
      ),
      dots
    )
  )
  graphics::axis(2, at = y, labels = labels, las = 1)
  graphics::segments(unweighted, y, weighted, y, col = "grey70")
  graphics::points(unweighted, y, pch = 1, col = "#D55E00")
  graphics::points(weighted, y, pch = 16, col = "#0072B2")
  graphics::abline(v = 0.1, lty = 3, col = "grey45")
  graphics::legend(
    "topright",
    legend = c(
      .wf_tr("plot_unweighted", lang = language),
      .wf_tr("plot_weighted", lang = language)
    ),
    col = c("#D55E00", "#0072B2"),
    pch = c(1, 16),
    bty = "n"
  )
  invisible(x)
}
