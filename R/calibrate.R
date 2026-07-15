#' Calibrate weights with a selected method
#'
#' Dispatches to the requested calibration engine while preserving the common
#' `wf_weights` return contract.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param method Calibration method: `"raking"`, `"poststrat"`, `"greg"`
#'   (linear GREG), `"logit"` (bounded, requires `bounds = c(L, U)`),
#'   `"soft"` (penalized margin relaxation), or `"ebal"` (entropy balancing).
#' @param ... Method-specific arguments. For `"greg"` / `"logit"`: `bounds`,
#'   `init_weight`, `na`, `id`, `tol`, `max_iter`, `precheck`. For `"soft"`:
#'   `tolerance`, `init_weight`, `na`, `id`, `max_outer`, `precheck`. For
#'   `"ebal"`: `moments`, `init_weight`, `na`, `id`, `tol`, `max_iter`,
#'   `precheck`.
#'
#' @return A `wf_weights` object.
#' @export
wf_calibrate <- function(sample, target, method = "raking", ...) {
  supported <- c("raking", "poststrat", "greg", "logit", "soft", "ebal")
  if (length(method) != 1 || !method %in% supported) {
    shown <- if (length(method) == 0) "<empty>" else as.character(method[[1]])
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
  if (identical(method, "ebal") && !is.null(dots$moments)) {
    .wf_warn_deprecated(
      paste(
        "Inline moment targets are deprecated because outcome-informed",
        "moments can steer weights; use verified external targets instead."
      ),
      feature = "wf_calibrate(..., moments =)",
      replacement = "wf_import_target() or wf_import_reference()",
      risk_code = "subjective_inline_moment_target"
    )
  }

  if (method == "raking") {
    out <- wf_rake(sample, target, ...)
    out$provenance$method <- "raking"
    return(out)
  }

  if (method == "poststrat") {
    return(wf_poststrat(sample, target, ...))
  }

  if (method == "soft") {
    return(.wf_softcalibrate(sample, target, ...))
  }

  bounds <- dots$bounds
  if (method == "logit") {
    if (is.null(bounds) || length(bounds) != 2 || !is.numeric(bounds) ||
        anyNA(bounds) || !(bounds[1] > 0 && bounds[1] < 1 && bounds[2] > 1)) {
      wf_abort(
        "method='logit' requires bounds = c(L, U) with 0 < L < 1 < U.",
        "wf_error_input", list(bounds = bounds)
      )
    }
  }
  if (method != "ebal" && !is.null(dots$moments)) {
    wf_abort(
      "`moments` is only supported for method = 'ebal'.",
      "wf_error_input"
    )
  }

  distance <- switch(method, greg = "linear", logit = "logit", ebal = "entropy")
  .wf_lincalibrate(sample, target, distance = distance, method = method, ...)
}
