#' Declare calibration dimensions
#'
#' @param ... Named dimension-level pairs. Use `NULL` to infer levels from the target.
#' @param .collapse Named list of collapse ladders.
#'
#' @return A `wf_dims` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(gender = c("female", "male"), age = c("young", "old"))
#' dims
wf_dims <- function(..., .collapse = list()) {
  vars <- list(...)
  if (length(vars) == 0 || is.null(names(vars)) || any(names(vars) == "")) {
    wf_abort(
      "wf_dims() requires named arguments: dimension = levels (or NULL).",
      "wf_error_input"
    )
  }
  vars <- lapply(vars, function(v) if (is.null(v)) NULL else .chr(v))
  bad <- setdiff(names(.collapse), names(vars))
  if (length(bad) > 0) {
    wf_abort(sprintf(
      "Collapse ladder(s) for unknown dimension(s): %s",
      paste(bad, collapse = ", ")
    ), "wf_error_input", list(unknown = bad))
  }
  structure(list(vars = vars, collapse = .collapse), class = "wf_dims")
}
