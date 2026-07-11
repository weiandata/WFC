#' Abort with a classed WFC condition.
#'
#' @param message Error message.
#' @param class Primary condition class.
#' @param data Machine-readable condition payload.
#' @keywords internal
#' @noRd
wf_abort <- function(message, class, data = list()) {
  stop(structure(
    class = c(class, "wf_error", "error", "condition"),
    list(message = message, call = sys.call(-1), data = data)
  ))
}

#' Warn with a classed WFC condition.
#'
#' @param message Warning message.
#' @param class Primary condition class.
#' @param data Machine-readable condition payload.
#' @keywords internal
#' @noRd
wf_warn <- function(message, class, data = list()) {
  warning(structure(
    class = c(class, "wf_warning", "warning", "condition"),
    list(message = message, call = sys.call(-1), data = data)
  ))
}

#' Warn about a deprecated WFC API.
#'
#' @param message Warning message.
#' @param feature Deprecated feature name.
#' @param replacement Suggested replacement, if any.
#' @keywords internal
#' @noRd
.wf_warn_deprecated <- function(message, feature = NULL, replacement = NULL) {
  wf_warn(
    message,
    "wf_warning_deprecated",
    list(feature = feature, replacement = replacement)
  )
}
