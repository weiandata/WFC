#' Calculate a SHA-256 identity for a file.
#'
#' @param path Path to an existing file.
#' @return A lowercase SHA-256 string.
#' @keywords internal
#' @noRd
.wf_sha256_file <- function(path) {
  if (!.wf_is_string(path) || !file.exists(path)) {
    .wf_safety_abort(
      "source_file_missing",
      "Source file does not exist.",
      "path"
    )
  }

  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

#' Calculate a stable SHA-256 identity for an R object.
#'
#' @param x Object to identify.
#' @return A lowercase SHA-256 string.
#' @keywords internal
#' @noRd
.wf_sha256_object <- function(x) {
  digest::digest(
    .wf_sanitize_for_hash(x),
    algo = "sha256",
    serialize = TRUE
  )
}
