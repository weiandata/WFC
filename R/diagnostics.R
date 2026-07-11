#' Diagnose calibrated weights
#'
#' Computes per-group quality metrics for a `wf_weights` object.
#'
#' @param w A `wf_weights` object.
#' @param target Optional `wf_target` object for residual margin checks.
#' @param sample Reserved for future diagnostics.
#' @param deff_ok Design-effect threshold for an OK verdict.
#' @param deff_caveat Design-effect threshold for caveat verdict.
#'
#' @return A `wf_diagnostics` object.
#' @export
wf_diagnose <- function(w, target = NULL, sample = NULL,
                        deff_ok = 3, deff_caveat = 10) {
  out <- lapply(split(w$data, w$data$group), function(d) {
    wt <- d$weight
    cv <- stats::sd(wt) / mean(wt)
    data.frame(
      group = d$group[1],
      n = nrow(d),
      ess = round(sum(wt)^2 / sum(wt^2), 1),
      deff = round(1 + cv^2, 2),
      mean_w = mean(wt),
      min_w = min(wt),
      max_w = max(wt),
      max_over_mean = round(max(wt) / mean(wt), 1),
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, out)
  log_cols <- intersect(c("group", "iterations", "converged", "trimmed"), names(w$log))
  tab <- merge(tab, w$log[, log_cols, drop = FALSE], by = "group", all.x = TRUE)
  if (!"iterations" %in% names(tab)) {
    tab$iterations <- NA_integer_
  }
  if (!"converged" %in% names(tab)) {
    tab$converged <- TRUE
  }
  if (!"trimmed" %in% names(tab)) {
    tab$trimmed <- 0L
  }

  if (!is.null(target) && !is.null(w$achieved)) {
    merr <- vapply(tab$group, function(g) {
      e <- 0
      for (d in target$dims) {
        tg <- target$groups[[g]]$margins[[d]]
        cur <- w$achieved[[g]][[d]][names(tg)]
        e <- max(e, max(abs(cur - tg) / tg))
      }
      e
    }, numeric(1))
    tab$margin_maxerr <- round(merr, 4)
  }

  tab$verdict <- ifelse(
    !tab$converged,
    "FAILED",
    ifelse(
      tab$deff <= deff_ok,
      "OK",
      ifelse(tab$deff <= deff_caveat, "usable with caveats", "do not publish separately")
    )
  )
  structure(list(table = tab), class = "wf_diagnostics")
}

#' Print diagnostics
#'
#' @param x A `wf_diagnostics` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_diagnostics <- function(x, ...) {
  cat("<wf_diagnostics>\n")
  print(x$table, row.names = FALSE)
  invisible(x)
}
