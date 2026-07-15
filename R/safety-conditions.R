#' Build a stable machine-readable safety payload.
#'
#' @param code Stable condition code.
#' @param severity Safety severity.
#' @param field Related input field, if any.
#' @param evidence Machine-readable supporting evidence.
#' @param next_actions Stable action codes available to the caller.
#' @keywords internal
#' @noRd
.wf_safety_payload <- function(code, severity, field, evidence, next_actions) {
  list(
    code = code,
    severity = severity,
    field = field,
    evidence = evidence,
    next_actions = as.character(next_actions)
  )
}

#' Abort with a classed safety condition.
#'
#' @inheritParams .wf_safety_payload
#' @param message Human-readable error message.
#' @keywords internal
#' @noRd
.wf_safety_abort <- function(code, message, field = NULL,
                             evidence = list(), next_actions = character()) {
  wf_abort(
    message,
    "wf_error_safety",
    .wf_safety_payload(code, "blocking", field, evidence, next_actions)
  )
}

#' Warn with a classed safety condition.
#'
#' @inheritParams .wf_safety_payload
#' @param message Human-readable warning message.
#' @keywords internal
#' @noRd
.wf_safety_warn <- function(code, message, field = NULL,
                            evidence = list(), next_actions = character()) {
  wf_warn(
    message,
    "wf_warning_safety",
    .wf_safety_payload(code, "review_required", field, evidence, next_actions)
  )
}

#' Build an informational safety record.
#'
#' @inheritParams .wf_safety_payload
#' @keywords internal
#' @noRd
.wf_safety_info <- function(code, field = NULL, evidence = list(),
                            next_actions = character()) {
  .wf_safety_payload(code, "informational", field, evidence, next_actions)
}
