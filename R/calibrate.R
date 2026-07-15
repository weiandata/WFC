#' Calibrate weights from verified design and target objects
#'
#' Enforces the WFC 2.0 verified-input boundary before dispatching to a
#' calibration engine. Raw data frames and ordinary `wf_target` objects are not
#' accepted.
#'
#' @param design An unchanged `wf_design_data` created by
#'   [wf_prepare_design()].
#' @param target An unchanged, non-demo `wf_verified_target` created by
#'   [wf_import_target()] or [wf_import_reference()].
#' @param method Calibration method: `"raking"`, `"poststrat"`, `"greg"`
#'   (linear GREG), `"logit"` (bounded), `"soft"` (declared margin
#'   relaxation), or `"ebal"` (categorical entropy balancing).
#' @param ... Method settings. ID and base-weight roles come from `design` and
#'   cannot be overridden. Inline target moments are not supported.
#'
#' @return A `wf_weights` object carrying the verified input identities.
#' @export
wf_calibrate <- function(design, target, method = "raking", ...) {
  dots <- list(...)
  if ("moments" %in% names(dots)) {
    .wf_safety_abort(
      "inline_moments_unsupported",
      paste(
        "WFC 2.0 does not accept inline target moments.",
        "Use verified external margins."
      ),
      "moments",
      next_actions = "import_verified_external_margins"
    )
  }
  .wf_execute_verified_engine(design, target, method, dots)
}

#' Dispatch one already-validated calibration engine.
#'
#' @param sample Internal design data frame.
#' @param target Internal verified target.
#' @param method Calibration method.
#' @param ... Engine settings.
#' @keywords internal
#' @noRd
.wf_calibrate_engine <- function(sample, target, method = "raking", ...) {
  supported <- c("raking", "poststrat", "greg", "logit", "soft", "ebal")
  if (length(method) != 1L || !method %in% supported) {
    shown <- if (length(method) == 0L) "<empty>" else as.character(method[[1]])
    wf_abort(
      sprintf(
        "Unsupported calibration method '%s'. Supported methods: %s.",
        shown,
        paste(supported, collapse = ", ")
      ),
      "wf_error_input",
      list(method = method)
    )
  }
  dots <- list(...)

  if (method == "raking") {
    out <- do.call(
      .wf_rake_engine,
      c(list(sample = sample, target = target), dots)
    )
    out$provenance$method <- "raking"
    return(out)
  }

  if (method == "poststrat") {
    return(do.call(
      .wf_poststrat_engine,
      c(list(sample = sample, target = target), dots)
    ))
  }

  if (method == "soft") {
    return(do.call(
      .wf_softcalibrate,
      c(list(sample = sample, target = target), dots)
    ))
  }

  bounds <- dots$bounds
  if (method == "logit") {
    if (is.null(bounds) || length(bounds) != 2L || !is.numeric(bounds) ||
        anyNA(bounds) || !(bounds[[1]] > 0 && bounds[[1]] < 1 &&
                           bounds[[2]] > 1)) {
      wf_abort(
        "method='logit' requires bounds = c(L, U) with 0 < L < 1 < U.",
        "wf_error_input",
        list(bounds = bounds)
      )
    }
  }

  distance <- switch(
    method,
    greg = "linear",
    logit = "logit",
    ebal = "entropy"
  )
  do.call(
    .wf_lincalibrate,
    c(
      list(
        sample = sample,
        target = target,
        distance = distance,
        method = method
      ),
      dots
    )
  )
}
