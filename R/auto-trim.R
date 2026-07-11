#' Recommend a weight-trimming cap
#'
#' Sweeps candidate upper caps by rerunning raking and reports the trade-off
#' between design effect and residual margin error. The function recommends a
#' cap but never applies it to a production result.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param id Optional unique unit identifier column.
#' @param caps Unique positive finite upper-cap multipliers.
#' @param lo Positive lower-cap multiplier used for every finite candidate.
#' @param max_deff Maximum acceptable worst-group design effect.
#' @param max_residual Maximum acceptable worst relative margin residual.
#' @param ... Additional arguments passed to [wf_rake()]. `trim` is not allowed
#'   because this function owns the candidate trim settings.
#'
#' @return A `wf_auto_trim` object containing the candidate frontier and the
#'   recommended cap. `Inf` means no trimming is needed; `NA` means no candidate
#'   meets both criteria.
#' @export
#' @examples
#' data(wfc_example)
#' target <- wf_target_population(
#'   wfc_example$population,
#'   c(gender = "gender", age = "age"),
#'   "count",
#'   wfc_example$dims,
#'   by = "province"
#' )
#' wf_auto_trim(wfc_example$sample, target, id = "id", caps = c(2, 4))
wf_auto_trim <- function(sample, target, id = NULL,
                         caps = c(2, 3, 4, 5, 6, 8, 10, 12),
                         lo = 0.05, max_deff = 6,
                         max_residual = 0.02, ...) {
  if (!is.data.frame(sample) || nrow(sample) == 0) {
    wf_abort("`sample` must be a non-empty data frame.", "wf_error_input")
  }
  if (!inherits(target, "wf_target")) {
    wf_abort("`target` must be a wf_target object.", "wf_error_input")
  }
  if (!is.numeric(caps) || length(caps) == 0 ||
      any(!is.finite(caps)) || any(caps <= 0) || anyDuplicated(caps)) {
    wf_abort(
      "`caps` must contain unique positive finite numbers.",
      "wf_error_input",
      list(caps = caps)
    )
  }
  if (length(lo) != 1 || !is.finite(lo) || lo <= 0 || any(caps <= lo)) {
    wf_abort(
      "`lo` must be positive and smaller than every candidate cap.",
      "wf_error_input",
      list(lo = lo)
    )
  }
  if (length(max_deff) != 1 || !is.finite(max_deff) || max_deff <= 0) {
    wf_abort("`max_deff` must be a positive finite number.", "wf_error_input")
  }
  if (length(max_residual) != 1 || !is.finite(max_residual) ||
      max_residual < 0) {
    wf_abort(
      "`max_residual` must be a non-negative finite number.",
      "wf_error_input"
    )
  }

  dots <- list(...)
  if ("trim" %in% names(dots)) {
    wf_abort(
      "`trim` cannot be supplied to wf_auto_trim(); use `caps` and `lo`.",
      "wf_error_input"
    )
  }

  t0 <- Sys.time()
  run_candidate <- function(cap) {
    warnings <- character()
    args <- c(
      list(
        sample = sample,
        target = target,
        id = id,
        trim = if (is.finite(cap)) c(lo, cap) else NULL
      ),
      dots
    )
    fit <- tryCatch(
      withCallingHandlers(
        do.call(wf_rake, args),
        warning = function(w) {
          warnings <<- c(warnings, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) e
    )

    if (inherits(fit, "error")) {
      return(data.frame(
        cap = cap,
        feasible = FALSE,
        worst_deff = NA_real_,
        worst_residual = NA_real_,
        warning_count = length(warnings),
        error_class = paste(class(fit), collapse = "/"),
        error_message = conditionMessage(fit),
        stringsAsFactors = FALSE
      ))
    }

    diagnostics <- wf_diagnose(fit, target = target)$table
    residual <- if ("margin_maxerr" %in% names(diagnostics)) {
      max(diagnostics$margin_maxerr, na.rm = TRUE)
    } else {
      NA_real_
    }
    data.frame(
      cap = cap,
      feasible = TRUE,
      worst_deff = max(diagnostics$deff, na.rm = TRUE),
      worst_residual = residual,
      warning_count = length(warnings),
      error_class = NA_character_,
      error_message = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  frontier <- do.call(rbind, lapply(c(sort(caps), Inf), run_candidate))
  frontier$meets_criteria <- frontier$feasible &
    is.finite(frontier$worst_deff) &
    frontier$worst_deff <= max_deff &
    is.finite(frontier$worst_residual) &
    frontier$worst_residual <= max_residual

  baseline_ok <- frontier$meets_criteria[is.infinite(frontier$cap)]
  finite_ok <- frontier$meets_criteria & is.finite(frontier$cap)
  recommended <- if (isTRUE(baseline_ok)) {
    Inf
  } else if (any(finite_ok)) {
    max(frontier$cap[finite_ok])
  } else {
    NA_real_
  }

  structure(
    list(
      frontier = frontier,
      recommended_cap = recommended,
      criteria = list(
        max_deff = max_deff,
        max_residual = max_residual,
        lo = lo
      ),
      provenance = list(
        method = "auto_trim",
        caps = sort(caps),
        id = id,
        created = t0,
        elapsed = as.numeric(Sys.time() - t0, units = "secs"),
        package_version = .wf_package_version()
      )
    ),
    class = "wf_auto_trim"
  )
}

#' Print an automatic trim recommendation
#'
#' @param x A `wf_auto_trim` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_auto_trim <- function(x, ...) {
  recommendation <- if (is.na(x$recommended_cap)) {
    "none meets the criteria"
  } else if (!is.finite(x$recommended_cap)) {
    "no trimming needed"
  } else {
    sprintf("%.3gx mean weight", x$recommended_cap)
  }
  cat("<wf_auto_trim> recommended cap:", recommendation, "\n")
  print(x$frontier, row.names = FALSE)
  invisible(x)
}
