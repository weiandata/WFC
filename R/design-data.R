#' Prepare outcome-free survey design data
#'
#' Creates a strict design object containing only identifiers, calibration
#' variables, and declared sampling-design fields. Any undeclared column blocks
#' construction so study outcomes cannot silently enter weight planning.
#'
#' @param data A data frame containing design variables only.
#' @param id Name of the unique, non-missing record identifier column.
#' @param calibration Names of columns permitted for calibration.
#' @param base_weight Optional name of a positive base-weight column.
#' @param strata Optional names of stratification columns.
#' @param clusters Optional names of cluster columns.
#' @param fpc Optional names of finite-population-correction columns.
#'
#' @return A `wf_design_data` object.
#' @export
wf_prepare_design <- function(data, id, calibration, base_weight = NULL,
                              strata = NULL, clusters = NULL, fpc = NULL) {
  roles <- list(
    id = id,
    calibration = calibration,
    base_weight = base_weight,
    strata = strata,
    clusters = clusters,
    fpc = fpc
  )
  assigned <- unique(unlist(roles, use.names = FALSE))

  .require_cols(data, assigned, "design data")

  extra <- setdiff(names(data), assigned)
  if (length(extra)) {
    .wf_safety_abort(
      "design_columns_unassigned",
      sprintf(
        "Design data contain unassigned column(s): %s.",
        paste(extra, collapse = ", ")
      ),
      evidence = list(columns = extra),
      next_actions = "remove_or_assign_columns"
    )
  }

  if (anyNA(data[[id]]) || anyDuplicated(data[[id]])) {
    .wf_safety_abort(
      "design_id_invalid",
      "Design IDs must be unique and non-missing.",
      id
    )
  }

  if (!is.null(base_weight) &&
      (any(!is.finite(data[[base_weight]])) ||
       any(data[[base_weight]] <= 0))) {
    .wf_safety_abort(
      "base_weight_invalid",
      "Base weights must be finite and positive.",
      base_weight
    )
  }

  structure(
    list(
      data = data,
      roles = roles,
      identity = .wf_sha256_object(list(data = data, roles = roles)),
      created = .wf_iso_time(),
      package_version = .wf_package_version()
    ),
    class = "wf_design_data"
  )
}

#' Print outcome-free survey design data
#'
#' @param x A `wf_design_data` object.
#' @param ... Reserved for future use.
#'
#' @return `x`, invisibly.
#' @export
print.wf_design_data <- function(x, ...) {
  cat("<wf_design_data>\n")
  cat(" Rows: ", nrow(x$data), "\n", sep = "")
  cat(" Calibration: ", paste(x$roles$calibration, collapse = ", "), "\n", sep = "")
  cat(" Identity: ", x$identity, "\n", sep = "")
  invisible(x)
}
