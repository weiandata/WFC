#' Require one suggested package.
#'
#' @param package Package name.
#' @param caller Human-readable caller description.
#' @keywords internal
#' @noRd
.wf_require_namespace <- function(package, caller) {
  if (!requireNamespace(package, quietly = TRUE)) {
    wf_abort(
      sprintf(
        "%s requires the suggested '%s' package. Install it with install.packages(\"%s\").",
        caller,
        package,
        package
      ),
      "wf_error_dependency",
      list(package = package, caller = caller)
    )
  }
  invisible(TRUE)
}

#' Validate forwarded interoperability arguments.
#'
#' @param dots Captured arguments.
#' @param reserved Argument names owned by WFC.
#' @param caller Function name.
#' @keywords internal
#' @noRd
.wf_interop_dots <- function(dots, reserved, caller) {
  if (length(dots) == 0) {
    return(invisible(dots))
  }
  if (is.null(names(dots)) || any(!nzchar(names(dots)))) {
    wf_abort(
      sprintf("All arguments in `%s` must be named.", caller),
      "wf_error_input"
    )
  }
  conflict <- intersect(names(dots), reserved)
  if (length(conflict) > 0) {
    wf_abort(
      sprintf(
        "%s owns argument(s): %s; they cannot be overridden through `...`.",
        caller,
        paste(conflict, collapse = ", ")
      ),
      "wf_error_input",
      list(arguments = conflict)
    )
  }
  invisible(dots)
}

#' Match a data frame to one WFC unit-ID vector.
#'
#' @param data User data frame.
#' @param id ID column name in `data`.
#' @param reference_ids WFC unit IDs.
#' @param reference Human-readable reference name.
#' @param caller Function name.
#' @return Integer positions in `reference_ids`, ordered like `data`.
#' @keywords internal
#' @noRd
.wf_match_unit_ids <- function(data, id, reference_ids, reference, caller) {
  if (length(id) != 1 || !is.character(id) || is.na(id) || !nzchar(id)) {
    wf_abort("`id` must be one non-empty column name.", "wf_error_input")
  }
  .require_cols(data, id, "data")
  data_ids <- .chr(data[[id]])
  reference_ids <- .chr(reference_ids)
  invalid_data <- is.na(data_ids) | !nzchar(data_ids)
  invalid_reference <- is.na(reference_ids) | !nzchar(reference_ids)
  if (any(invalid_data) || any(invalid_reference)) {
    wf_abort(
      sprintf("%s requires non-missing, non-empty unit IDs.", caller),
      "wf_error_schema",
      list(
        invalid_data = which(invalid_data),
        invalid_reference = which(invalid_reference)
      )
    )
  }
  if (anyDuplicated(data_ids)) {
    duplicated_ids <- unique(data_ids[duplicated(data_ids)])
    wf_abort(
      sprintf(
        "`data[[%s]]` contains duplicate unit IDs: %s.",
        id,
        paste(utils::head(duplicated_ids, 5), collapse = ", ")
      ),
      "wf_error_schema",
      list(ids = duplicated_ids, source = "data")
    )
  }
  if (anyDuplicated(reference_ids)) {
    duplicated_ids <- unique(reference_ids[duplicated(reference_ids)])
    wf_abort(
      sprintf(
        "%s contains duplicate unit IDs: %s.",
        reference,
        paste(utils::head(duplicated_ids, 5), collapse = ", ")
      ),
      "wf_error_schema",
      list(ids = duplicated_ids, source = reference)
    )
  }

  missing_weights <- setdiff(data_ids, reference_ids)
  extra_weights <- setdiff(reference_ids, data_ids)
  if (length(missing_weights) > 0 || length(extra_weights) > 0) {
    wf_abort(
      sprintf(
        "%s requires identical unit-ID sets; %d data ID(s) lack weights and %d weight ID(s) lack data rows.",
        caller,
        length(missing_weights),
        length(extra_weights)
      ),
      "wf_error_schema",
      list(
        missing_weights = missing_weights,
        extra_weights = extra_weights
      )
    )
  }
  match(data_ids, reference_ids)
}

#' Convert WFC weights to a survey design
#'
#' Joins calibrated WFC weights onto an analysis data frame by exact unit ID and
#' creates a standard `survey::svydesign()` object. The `survey` package remains
#' a suggested dependency.
#'
#' @param w A `wf_weights` object.
#' @param data Non-empty analysis data frame containing the units in `w`.
#' @param id Unit-ID column in `data`; matched to `w$data$id`.
#' @param ids Survey cluster formula, defaulting to independent units.
#' @param strata Optional survey strata formula.
#' @param fpc Optional finite-population-correction formula.
#' @param nest Whether cluster IDs should be relabeled to nest within strata.
#' @param ... Additional arguments passed to `survey::svydesign()`. WFC owns
#'   `weights` and `probs`; they cannot be overridden.
#'
#' @return A standard `survey.design2` object whose variables include the
#'   aligned `.wf_weight` column.
#' @export
as_svydesign <- function(w, data, id = "id",
                         ids = ~1, strata = NULL, fpc = NULL,
                         nest = FALSE, ...) {
  if (!inherits(w, "wf_weights")) {
    wf_abort("`w` must be a wf_weights object.", "wf_error_input")
  }
  if (!is.data.frame(data) || nrow(data) == 0) {
    wf_abort("`data` must be a non-empty data frame.", "wf_error_input")
  }
  if (!is.data.frame(w$data) ||
      !all(c("id", "weight") %in% names(w$data))) {
    wf_abort(
      "`w` is missing its required unit ID or weight data.",
      "wf_error_internal"
    )
  }
  if (".wf_weight" %in% names(data)) {
    wf_abort(
      "`data` already contains reserved column '.wf_weight'.",
      "wf_error_schema"
    )
  }
  weight <- as.numeric(w$data$weight)
  if (anyNA(weight) || any(!is.finite(weight)) || any(weight < 0)) {
    wf_abort(
      "`w$data$weight` must contain finite non-negative values.",
      "wf_error_internal"
    )
  }

  dots <- list(...)
  .wf_interop_dots(dots, c("weights", "probs"), "as_svydesign()")
  order <- .wf_match_unit_ids(
    data,
    id,
    w$data$id,
    "`w$data$id`",
    "as_svydesign()"
  )
  variables <- data
  variables$.wf_weight <- weight[order]

  .wf_require_namespace("survey", "as_svydesign()")
  design <- do.call(
    survey::svydesign,
    c(
      list(
        ids = ids,
        strata = strata,
        fpc = fpc,
        data = variables,
        nest = nest,
        weights = stats::as.formula("~.wf_weight")
      ),
      dots
    )
  )
  attr(design, "wfc_provenance") <- w$provenance
  design
}

#' Convert WFC replicate weights to a survey replicate design
#'
#' Aligns recalibrated WFC replicate weights to analysis data by exact unit ID
#' and creates a standard `survey::svrepdesign()` object. The returned design
#' uses full-estimate-centered (`mse = TRUE`) variance so its estimates reproduce
#' [wf_variance()].
#'
#' @param r A `wf_replicate_weights` object.
#' @param data Non-empty analysis data frame containing the units in `r`.
#' @param id Unit-ID column in `data`; matched to `r$base$id`.
#' @param degf Optional survey design degrees of freedom.
#' @param ... Additional arguments passed to `survey::svrepdesign()`. WFC owns
#'   the variables, base/replicate weights, replication type and scales,
#'   combined-weight setting, and MSE setting.
#'
#' @return A standard `svyrep.design` object whose variables include the aligned
#'   `.wf_weight` base-weight column.
#' @export
as_svrepdesign <- function(r, data, id = "id", degf = NULL, ...) {
  if (!inherits(r, "wf_replicate_weights")) {
    wf_abort(
      "`r` must be a wf_replicate_weights object.",
      "wf_error_input"
    )
  }
  if (!is.data.frame(data) || nrow(data) == 0) {
    wf_abort("`data` must be a non-empty data frame.", "wf_error_input")
  }
  if (".wf_weight" %in% names(data)) {
    wf_abort(
      "`data` already contains reserved column '.wf_weight'.",
      "wf_error_schema"
    )
  }
  if (!is.data.frame(r$base) ||
      !all(c("id", "weight") %in% names(r$base)) ||
      !is.matrix(r$replicates) || nrow(r$replicates) != nrow(r$base) ||
      ncol(r$replicates) == 0) {
    wf_abort(
      "`r` has malformed base or replicate weight data.",
      "wf_error_internal"
    )
  }
  base_weight <- as.numeric(r$base$weight)
  replicate_weight <- r$replicates
  if (anyNA(base_weight) || any(!is.finite(base_weight)) ||
      any(base_weight < 0) || anyNA(replicate_weight) ||
      any(!is.finite(replicate_weight)) || any(replicate_weight < 0)) {
    wf_abort(
      "`r` contains invalid base or replicate weights.",
      "wf_error_internal"
    )
  }
  if (length(r$scale) != 1 || !is.numeric(r$scale) ||
      !is.finite(r$scale) || r$scale <= 0 ||
      !is.numeric(r$rscales) || length(r$rscales) != ncol(r$replicates) ||
      anyNA(r$rscales) || any(!is.finite(r$rscales)) ||
      any(r$rscales <= 0)) {
    wf_abort(
      "`r` contains invalid replication scale metadata.",
      "wf_error_internal"
    )
  }
  if (length(r$method) != 1 ||
      !r$method %in% c("bootstrap", "jackknife", "brr")) {
    wf_abort(
      "`r` contains an unsupported replication method.",
      "wf_error_internal",
      list(method = r$method)
    )
  }
  if (!is.null(degf) &&
      (length(degf) != 1 || !is.numeric(degf) || !is.finite(degf) ||
       degf < 0)) {
    wf_abort("`degf` must be NULL or a non-negative number.", "wf_error_input")
  }

  dots <- list(...)
  reserved <- c(
    "variables", "repweights", "weights", "type", "scale", "rscales",
    "combined.weights", "mse", "rho"
  )
  .wf_interop_dots(dots, reserved, "as_svrepdesign()")
  order <- .wf_match_unit_ids(
    data,
    id,
    r$base$id,
    "`r$base$id`",
    "as_svrepdesign()"
  )
  variables <- data
  variables$.wf_weight <- base_weight[order]
  replicate_weight <- replicate_weight[order, , drop = FALSE]

  survey_type <- switch(
    r$method,
    bootstrap = "bootstrap",
    jackknife = if (is.null(r$design$strata)) "JK1" else "JKn",
    brr = if (!is.null(r$rho) && r$rho > 0) "Fay" else "BRR"
  )
  if (survey_type == "BRR" &&
      !isTRUE(all.equal(r$scale, 1 / ncol(replicate_weight), tolerance = 1e-12))) {
    wf_abort(
      "BRR replication metadata does not use the required 1 / R scale.",
      "wf_error_internal",
      list(scale = r$scale, expected = 1 / ncol(replicate_weight))
    )
  }

  .wf_require_namespace("survey", "as_svrepdesign()")
  args <- list(
    variables = variables,
    repweights = replicate_weight,
    weights = base_weight[order],
    type = survey_type,
    rscales = r$rscales,
    combined.weights = TRUE,
    mse = TRUE,
    degf = degf
  )
  if (survey_type == "Fay") {
    args$rho <- r$rho
  }
  if (survey_type != "BRR" && survey_type != "Fay") {
    args$scale <- r$scale
  }
  design <- do.call(survey::svrepdesign, c(args, dots))
  if (!isTRUE(all.equal(design$scale, r$scale, tolerance = 1e-12)) ||
      !isTRUE(all.equal(design$rscales, r$rscales, tolerance = 1e-12))) {
    wf_abort(
      "survey::svrepdesign() did not preserve WFC replication scales.",
      "wf_error_internal"
    )
  }
  attr(design, "wfc_provenance") <- r$provenance
  design
}
