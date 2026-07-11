#' Broom-style projections for WFC results
#'
#' These S3 methods return base data frames and are registered for the generic
#' names supplied by the suggested `generics` package. They do not require or
#' return tibbles, and all programmatic column names remain stable English keys.
#'
#' @param x A supported WFC result object.
#' @param data Analysis data to augment with unit weights.
#' @param id Unit-ID column in `data`, matched to `x$data$id`.
#' @param ... Additional arguments. `augment.wf_weights()` does not accept
#'   additional arguments.
#'
#' @return `tidy()` returns an object's primary detail table. `glance()` returns
#'   a one-row summary. `augment()` returns `data` with `.weight` and `.feature`
#'   appended in data-row order.
#' @name wfc-tidiers
NULL

#' @rdname wfc-tidiers
#' @exportS3Method generics::tidy
tidy.wf_weights <- function(x, ...) {
  x$data
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::tidy
tidy.wf_diagnostics <- function(x, ...) {
  x$table
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::tidy
tidy.wf_blend_result <- function(x, ...) {
  if (is.data.frame(x$estimates) && nrow(x$estimates) > 0) {
    return(x$estimates)
  }
  if (is.data.frame(x$cell_weights)) {
    return(x$cell_weights)
  }
  data.frame()
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::tidy
tidy.wf_variance_result <- function(x, ...) {
  x$table
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::glance
glance.wf_weights <- function(x, ...) {
  weight <- as.numeric(x$data$weight)
  total <- sum(weight)
  sum_squares <- sum(weight^2)
  ess <- if (sum_squares > 0) total^2 / sum_squares else NA_real_
  deff <- if (length(weight) > 1 && mean(weight) > 0) {
    1 + (stats::sd(weight) / mean(weight))^2
  } else {
    NA_real_
  }
  method <- x$provenance$method
  if (is.null(method) || length(method) == 0 || is.na(method[[1]])) {
    method <- "raking"
  }
  data.frame(
    n = nrow(x$data),
    groups = length(unique(x$data$group)),
    total_weight = total,
    ess = ess,
    deff = deff,
    method = as.character(method[[1]]),
    stringsAsFactors = FALSE
  )
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::glance
glance.wf_diagnostics <- function(x, ...) {
  table <- x$table
  verdict <- as.character(table$verdict)
  ok <- sum(verdict == "OK", na.rm = TRUE)
  caveat <- sum(verdict == "usable with caveats", na.rm = TRUE)
  failed <- nrow(table) - ok - caveat
  worst_deff <- if (nrow(table) > 0 && any(is.finite(table$deff))) {
    max(table$deff[is.finite(table$deff)])
  } else {
    NA_real_
  }
  minimum_ess <- if (nrow(table) > 0 && any(is.finite(table$ess))) {
    min(table$ess[is.finite(table$ess)])
  } else {
    NA_real_
  }
  data.frame(
    groups = nrow(table),
    ok = ok,
    caveat = caveat,
    failed = failed,
    worst_deff = worst_deff,
    minimum_ess = minimum_ess,
    stringsAsFactors = FALSE
  )
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::glance
glance.wf_blend_result <- function(x, ...) {
  lambda <- x$lambda
  values <- if (is.data.frame(lambda) && "lambda" %in% names(lambda)) {
    as.numeric(lambda$lambda)
  } else {
    numeric()
  }
  groups <- if (is.data.frame(lambda) && "group" %in% names(lambda)) {
    length(unique(lambda$group))
  } else {
    0L
  }
  lambda_min <- if (length(values) > 0) min(values) else NA_real_
  lambda_mean <- if (length(values) > 0) mean(values) else NA_real_
  lambda_max <- if (length(values) > 0) max(values) else NA_real_
  trimmed <- x$diagnostics$trimmed_lambda_count
  one_source <- x$diagnostics$one_source_cell_count
  data.frame(
    cells = if (is.data.frame(lambda)) nrow(lambda) else 0L,
    groups = groups,
    lambda_min = lambda_min,
    lambda_mean = lambda_mean,
    lambda_max = lambda_max,
    trimmed_lambda_count = if (is.null(trimmed)) NA_integer_ else trimmed,
    one_source_cell_count = if (is.null(one_source)) NA_integer_ else one_source,
    stringsAsFactors = FALSE
  )
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::glance
glance.wf_variance_result <- function(x, ...) {
  table <- x$table
  maximum_se <- if (is.data.frame(table) && nrow(table) > 0 &&
      any(is.finite(table$se))) {
    max(table$se[is.finite(table$se)])
  } else {
    NA_real_
  }
  data.frame(
    method = as.character(x$provenance$method),
    replicates = as.integer(x$provenance$R),
    level = as.numeric(x$provenance$level),
    ci = as.character(x$provenance$ci),
    quantities = if (is.data.frame(table)) nrow(table) else 0L,
    maximum_se = maximum_se,
    stringsAsFactors = FALSE
  )
}

#' @rdname wfc-tidiers
#' @exportS3Method generics::augment
augment.wf_weights <- function(x, data, id = "id", ...) {
  if (!is.data.frame(data) || nrow(data) == 0) {
    wf_abort("`data` must be a non-empty data frame.", "wf_error_input")
  }
  dots <- list(...)
  if (length(dots) > 0) {
    wf_abort(
      "augment.wf_weights() does not accept additional arguments.",
      "wf_error_input",
      list(arguments = names(dots))
    )
  }
  collision <- intersect(c(".weight", ".feature"), names(data))
  if (length(collision) > 0) {
    wf_abort(
      sprintf(
        "`data` already contains reserved augment column(s): %s.",
        paste(collision, collapse = ", ")
      ),
      "wf_error_schema",
      list(columns = collision)
    )
  }
  if (!is.data.frame(x$data) ||
      !all(c("id", "weight", "feature") %in% names(x$data))) {
    wf_abort(
      "`x` is missing required unit ID, weight, or feature data.",
      "wf_error_internal"
    )
  }
  order <- .wf_match_unit_ids(
    data,
    id,
    x$data$id,
    "`x$data$id`",
    "augment.wf_weights()"
  )
  out <- data
  out$.weight <- x$data$weight[order]
  out$.feature <- x$data$feature[order]
  out
}
