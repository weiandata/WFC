#' Return the loaded package version for blend provenance.
#'
#' @keywords internal
#' @noRd
.wf_blend_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("WFC")),
    error = function(e) "0.5.0"
  )
}

#' Validate one argument against allowed values without partial matching.
#'
#' @param value User-supplied scalar character value.
#' @param choices Supported values.
#' @param arg Argument name for error messages.
#' @keywords internal
#' @noRd
.wf_blend_match <- function(value, choices, arg) {
  if (length(value) == length(choices) && identical(value, choices)) {
    value <- value[[1]]
  }
  if (length(value) != 1 || is.na(value) || !value %in% choices) {
    shown <- if (length(value) == 0) "<empty>" else as.character(value[[1]])
    wf_abort(
      sprintf(
        "Unsupported %s '%s'. Supported values: %s.",
        arg,
        shown,
        paste(choices, collapse = ", ")
      ),
      "wf_error_input",
      stats::setNames(list(value), arg)
    )
  }
  value
}

#' Validate a blend cell variable vector.
#'
#' @param by_cell Requested cell columns.
#' @keywords internal
#' @noRd
.wf_blend_by_cell <- function(by_cell) {
  if (!is.character(by_cell) || length(by_cell) < 1 || any(is.na(by_cell)) || any(by_cell == "")) {
    wf_abort("`by_cell` must contain at least one non-empty column name.", "wf_error_input")
  }
  if (anyDuplicated(by_cell)) {
    wf_abort("`by_cell` must not contain duplicated column names.", "wf_error_input")
  }
  by_cell
}

#' Validate trim bounds for data-driven lambdas.
#'
#' @param trim_lambda Two finite bounds in increasing order.
#' @keywords internal
#' @noRd
.wf_blend_trim <- function(trim_lambda) {
  if (!is.numeric(trim_lambda) || length(trim_lambda) != 2 ||
    any(is.na(trim_lambda)) || any(!is.finite(trim_lambda)) ||
    trim_lambda[[1]] < 0 || trim_lambda[[2]] > 1 ||
    trim_lambda[[1]] > trim_lambda[[2]]) {
    wf_abort("`trim_lambda` must be two finite increasing values inside [0, 1].", "wf_error_input")
  }
  as.numeric(trim_lambda)
}

#' Validate one wf_weights source for blending.
#'
#' @param source Input object.
#' @param label Source label.
#' @param by_cell Cell columns.
#' @param outcome Optional outcome column.
#' @keywords internal
#' @noRd
.wf_blend_check_source <- function(source, label, by_cell, outcome) {
  if (!inherits(source, "wf_weights")) {
    wf_abort(
      sprintf("`%s` must be a wf_weights object.", label),
      "wf_error_input",
      list(source = label)
    )
  }
  if (!is.data.frame(source$data)) {
    wf_abort(
      sprintf("`%s$data` must be a data frame.", label),
      "wf_error_schema",
      list(source = label)
    )
  }

  required <- c("group", "weight", by_cell)
  if (!is.null(outcome)) {
    required <- c(required, outcome)
  }
  .require_cols(source$data, required, sprintf("%s$data", label))

  weight <- source$data$weight
  if (!is.numeric(weight) || any(is.na(weight)) || any(!is.finite(weight)) || any(weight < 0)) {
    wf_abort(
      sprintf("`%s$data$weight` must be finite, non-missing, and non-negative.", label),
      "wf_error_input",
      list(source = label)
    )
  }

  group <- .chr(source$data$group)
  if (any(is.na(group)) || any(group == "")) {
    wf_abort(
      sprintf("`%s$data$group` must not contain missing or empty values.", label),
      "wf_error_input",
      list(source = label)
    )
  }

  for (cell_col in by_cell) {
    cell_value <- .chr(source$data[[cell_col]])
    if (any(is.na(cell_value)) || any(cell_value == "")) {
      wf_abort(
        sprintf("`%s$data$%s` must not contain missing or empty values.", label, cell_col),
        "wf_error_input",
        list(source = label, column = cell_col)
      )
    }
  }

  if (!is.null(outcome)) {
    y <- source$data[[outcome]]
    if (!is.numeric(y) || all(is.na(y))) {
      wf_abort(
        sprintf("`%s$data$%s` must be numeric and not entirely missing.", label, outcome),
        "wf_error_input",
        list(source = label, outcome = outcome)
      )
    }
  }

  invisible(source)
}

#' Validate fixed lambda settings.
#'
#' @param lambda Strategy.
#' @param lambda_fixed User-supplied fixed lambda.
#' @keywords internal
#' @noRd
.wf_blend_check_fixed_required <- function(lambda, lambda_fixed) {
  if (lambda == "fixed" && is.null(lambda_fixed)) {
    wf_abort("`lambda_fixed` is required when `lambda = \"fixed\"`.", "wf_error_input")
  }
  invisible(lambda_fixed)
}

#' Build grouping keys for blend summaries.
#'
#' @param data Source data.
#' @param by_cell Cell columns.
#' @keywords internal
#' @noRd
.wf_blend_key <- function(data, by_cell) {
  key_data <- data.frame(group = .chr(data$group), stringsAsFactors = FALSE)
  for (cell_col in by_cell) {
    key_data[[cell_col]] <- .chr(data[[cell_col]])
  }
  .wf_cell_key(as.matrix(key_data), names(key_data))
}

#' Summarize one source by cell.
#'
#' @param source Source `wf_weights`.
#' @param label Source label.
#' @param by_cell Cell columns.
#' @param outcome Optional outcome column.
#' @keywords internal
#' @noRd
.wf_blend_source_cells <- function(source, label, by_cell, outcome) {
  data <- source$data
  key <- .wf_blend_key(data, by_cell)
  split_rows <- split(seq_len(nrow(data)), key)
  rows <- lapply(split_rows, function(idx) {
    part <- data[idx, , drop = FALSE]
    w_all <- as.numeric(part$weight)
    key_values <- data.frame(
      group = .chr(part$group[[1]]),
      stringsAsFactors = FALSE
    )
    for (cell_col in by_cell) {
      key_values[[cell_col]] <- .chr(part[[cell_col]][[1]])
    }

    if (is.null(outcome)) {
      estimate <- NA_real_
      variance <- NA_real_
      missing_outcome <- NA_integer_
      contributing <- w_all > 0
      w <- w_all[contributing]
    } else {
      y_all <- part[[outcome]]
      contributing <- w_all > 0 & !is.na(y_all)
      w <- w_all[contributing]
      y <- y_all[contributing]
      missing_outcome <- sum(is.na(y_all))
      if (length(w) > 0 && sum(w) > 0) {
        estimate <- sum(w * y) / sum(w)
        variance <- sum((w^2) * ((y - estimate)^2)) / (sum(w)^2)
      } else {
        estimate <- NA_real_
        variance <- NA_real_
      }
    }

    weight_sum <- sum(w)
    neff <- if (length(w) > 0 && sum(w^2) > 0) {
      (sum(w)^2) / sum(w^2)
    } else {
      0
    }

    cbind(
      key_values,
      data.frame(
        row_count = length(idx),
        weight_sum = weight_sum,
        neff = neff,
        estimate = estimate,
        variance = variance,
        missing_outcome = missing_outcome,
        estimable = if (is.null(outcome)) weight_sum > 0 else is.finite(estimate),
        stringsAsFactors = FALSE
      )
    )
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  stat_cols <- c(
    "row_count", "weight_sum", "neff", "estimate",
    "variance", "missing_outcome", "estimable"
  )
  names(out)[names(out) %in% stat_cols] <- paste0(
    names(out)[names(out) %in% stat_cols],
    "_",
    label
  )
  out
}

#' Summarize one source by group for group-level lambda.
#'
#' @param source Source `wf_weights`.
#' @param label Source label.
#' @param outcome Optional outcome column.
#' @keywords internal
#' @noRd
.wf_blend_source_groups <- function(source, label, outcome) {
  data <- source$data
  split_rows <- split(seq_len(nrow(data)), .chr(data$group))
  rows <- lapply(names(split_rows), function(group_name) {
    idx <- split_rows[[group_name]]
    part <- data[idx, , drop = FALSE]
    w_all <- as.numeric(part$weight)

    if (is.null(outcome)) {
      estimate <- NA_real_
      variance <- NA_real_
      missing_outcome <- NA_integer_
      contributing <- w_all > 0
      w <- w_all[contributing]
    } else {
      y_all <- part[[outcome]]
      contributing <- w_all > 0 & !is.na(y_all)
      w <- w_all[contributing]
      y <- y_all[contributing]
      missing_outcome <- sum(is.na(y_all))
      if (length(w) > 0 && sum(w) > 0) {
        estimate <- sum(w * y) / sum(w)
        variance <- sum((w^2) * ((y - estimate)^2)) / (sum(w)^2)
      } else {
        estimate <- NA_real_
        variance <- NA_real_
      }
    }

    weight_sum <- sum(w)
    neff <- if (length(w) > 0 && sum(w^2) > 0) {
      (sum(w)^2) / sum(w^2)
    } else {
      0
    }

    data.frame(
      group = group_name,
      row_count = length(idx),
      weight_sum = weight_sum,
      neff = neff,
      estimate = estimate,
      variance = variance,
      missing_outcome = missing_outcome,
      estimable = if (is.null(outcome)) weight_sum > 0 else is.finite(estimate),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  stat_cols <- c(
    "row_count", "weight_sum", "neff", "estimate",
    "variance", "missing_outcome", "estimable"
  )
  names(out)[names(out) %in% stat_cols] <- paste0(
    names(out)[names(out) %in% stat_cols],
    "_",
    label
  )
  out
}

#' Merge online and offline cell summaries.
#'
#' @param online_cells Online cell summary.
#' @param offline_cells Offline cell summary.
#' @param by_cell Cell columns.
#' @keywords internal
#' @noRd
.wf_blend_merge_cells <- function(online_cells, offline_cells, by_cell) {
  keys <- c("group", by_cell)
  merged <- merge(
    online_cells,
    offline_cells,
    by = keys,
    all = TRUE,
    sort = FALSE
  )
  numeric_zero <- c(
    "row_count_online", "weight_sum_online", "neff_online",
    "missing_outcome_online", "row_count_offline",
    "weight_sum_offline", "neff_offline", "missing_outcome_offline"
  )
  for (col in intersect(numeric_zero, names(merged))) {
    merged[[col]][is.na(merged[[col]])] <- 0
  }
  logical_false <- c("estimable_online", "estimable_offline")
  for (col in intersect(logical_false, names(merged))) {
    merged[[col]][is.na(merged[[col]])] <- FALSE
  }
  merged
}

#' Compute data-driven lambda from effective sample sizes.
#'
#' @param cells Merged source cells.
#' @keywords internal
#' @noRd
.wf_blend_lambda_neff <- function(cells) {
  denom <- cells$neff_online + cells$neff_offline
  ifelse(denom > 0, cells$neff_online / denom, NA_real_)
}

#' Compute inverse-variance lambda.
#'
#' @param cells Merged source cells or groups.
#' @keywords internal
#' @noRd
.wf_blend_lambda_inverse_variance <- function(cells) {
  vo <- cells$variance_online
  vf <- cells$variance_offline
  denom <- vo + vf
  lambda <- ifelse(is.finite(denom) & denom > 0, vf / denom, NA_real_)
  zero_zero <- is.finite(vo) & is.finite(vf) & vo == 0 & vf == 0
  if (any(zero_zero)) {
    lambda[zero_zero] <- .wf_blend_lambda_neff(cells[zero_zero, , drop = FALSE])
  }
  lambda
}

#' Apply lambda trimming and one-source overrides.
#'
#' @param cells Merged source cells.
#' @param lambda_raw Raw lambda values.
#' @param lambda_strategy Strategy name.
#' @param trim_lambda Trim bounds.
#' @keywords internal
#' @noRd
.wf_blend_finalize_lambda <- function(cells, lambda_raw, lambda_strategy, trim_lambda) {
  online_ok <- cells$estimable_online
  offline_ok <- cells$estimable_offline

  lambda <- lambda_raw
  reason <- rep(lambda_strategy, length(lambda))
  trimmed <- rep(FALSE, length(lambda))

  only_online <- online_ok & !offline_ok
  only_offline <- !online_ok & offline_ok
  no_source <- !online_ok & !offline_ok
  both <- online_ok & offline_ok

  lambda[only_online] <- 1
  reason[only_online] <- "online_only"
  lambda[only_offline] <- 0
  reason[only_offline] <- "offline_only"

  trim_hit <- both & is.finite(lambda) &
    (lambda < trim_lambda[[1]] | lambda > trim_lambda[[2]])
  lambda[trim_hit] <- pmin(
    pmax(lambda[trim_hit], trim_lambda[[1]]),
    trim_lambda[[2]]
  )
  reason[trim_hit] <- "trimmed"
  trimmed[trim_hit] <- TRUE

  if (any(no_source)) {
    wf_abort(
      "At least one fusion cell has no estimable source.",
      "wf_error_feasibility",
      list(rows = which(no_source))
    )
  }

  data.frame(
    lambda = lambda,
    lambda_reason = reason,
    lambda_trimmed = trimmed,
    stringsAsFactors = FALSE
  )
}

#' Build scalar fixed lambda values.
#'
#' @param lambda_fixed User-supplied fixed lambda.
#' @param n Number of rows.
#' @keywords internal
#' @noRd
.wf_blend_fixed_scalar <- function(lambda_fixed, n) {
  if (!is.numeric(lambda_fixed) || length(lambda_fixed) != 1 ||
    is.na(lambda_fixed) || !is.finite(lambda_fixed) ||
    lambda_fixed < 0 || lambda_fixed > 1) {
    wf_abort("Scalar `lambda_fixed` must be one finite value inside [0, 1].", "wf_error_input")
  }
  rep(as.numeric(lambda_fixed), n)
}

#' Resolve fixed lambda values for cells.
#'
#' @param lambda_fixed Scalar or data frame.
#' @param cells Merged source cells.
#' @param level Lambda level.
#' @param by_cell Cell columns.
#' @keywords internal
#' @noRd
.wf_blend_fixed_lambda <- function(lambda_fixed, cells, level, by_cell) {
  if (is.numeric(lambda_fixed) && length(lambda_fixed) == 1) {
    return(.wf_blend_fixed_scalar(lambda_fixed, nrow(cells)))
  }
  if (!is.data.frame(lambda_fixed)) {
    wf_abort("`lambda_fixed` must be a scalar or data frame.", "wf_error_input")
  }

  keys <- if (level == "group") "group" else c("group", by_cell)
  .require_cols(lambda_fixed, c(keys, "lambda"), "`lambda_fixed`")
  if (!is.numeric(lambda_fixed$lambda) || any(is.na(lambda_fixed$lambda)) ||
    any(!is.finite(lambda_fixed$lambda)) || any(lambda_fixed$lambda < 0) ||
    any(lambda_fixed$lambda > 1)) {
    wf_abort("`lambda_fixed$lambda` must contain finite values inside [0, 1].", "wf_error_input")
  }

  lambda_key <- .wf_cell_key(as.matrix(lambda_fixed[, keys, drop = FALSE]), keys)
  if (anyDuplicated(lambda_key)) {
    wf_abort("`lambda_fixed` contains duplicate keys.", "wf_error_input")
  }

  cell_key <- .wf_cell_key(as.matrix(cells[, keys, drop = FALSE]), keys)
  idx <- match(cell_key, lambda_key)
  if (any(is.na(idx))) {
    wf_abort(
      "`lambda_fixed` does not provide lambda values for every requested output cell.",
      "wf_error_input"
    )
  }
  lambda_fixed$lambda[idx]
}

#' Merge source group summaries.
#'
#' @param online_groups Online group summary.
#' @param offline_groups Offline group summary.
#' @keywords internal
#' @noRd
.wf_blend_merge_groups <- function(online_groups, offline_groups) {
  merged <- merge(
    online_groups,
    offline_groups,
    by = "group",
    all = TRUE,
    sort = FALSE
  )
  numeric_zero <- c(
    "row_count_online", "weight_sum_online", "neff_online",
    "missing_outcome_online", "row_count_offline",
    "weight_sum_offline", "neff_offline", "missing_outcome_offline"
  )
  for (col in intersect(numeric_zero, names(merged))) {
    merged[[col]][is.na(merged[[col]])] <- 0
  }
  logical_false <- c("estimable_online", "estimable_offline")
  for (col in intersect(logical_false, names(merged))) {
    merged[[col]][is.na(merged[[col]])] <- FALSE
  }
  merged
}

#' Build lambda at the requested level and merge it to cells.
#'
#' @param online Online source.
#' @param offline Offline source.
#' @param cells Cell-level source summary.
#' @param by_cell Cell columns.
#' @param outcome Optional outcome.
#' @param lambda Strategy.
#' @param lambda_fixed Fixed lambda.
#' @param level Lambda level.
#' @param trim_lambda Trim bounds.
#' @keywords internal
#' @noRd
.wf_blend_lambda_for_level <- function(online, offline, cells, by_cell, outcome,
                                       lambda, lambda_fixed, level, trim_lambda) {
  keys <- c("group", by_cell)
  if (level == "group" && lambda != "fixed") {
    online_groups <- .wf_blend_source_groups(online, "online", outcome)
    offline_groups <- .wf_blend_source_groups(offline, "offline", outcome)
    base <- .wf_blend_merge_groups(online_groups, offline_groups)
    lambda_raw <- switch(
      lambda,
      neff = .wf_blend_lambda_neff(base),
      inverse_variance = .wf_blend_lambda_inverse_variance(base)
    )
    lambda_info <- .wf_blend_finalize_lambda(base, lambda_raw, lambda, trim_lambda)
    lambda_table <- cbind(base["group"], lambda_info)
    idx <- match(cells$group, lambda_table$group)
    out <- cbind(cells[keys], lambda_table[idx, c("lambda", "lambda_reason", "lambda_trimmed")])
  } else {
    lambda_raw <- switch(
      lambda,
      neff = .wf_blend_lambda_neff(cells),
      inverse_variance = .wf_blend_lambda_inverse_variance(cells),
      fixed = .wf_blend_fixed_lambda(lambda_fixed, cells, level, by_cell)
    )
    lambda_info <- .wf_blend_finalize_lambda(cells, lambda_raw, lambda, trim_lambda)
    out <- cbind(cells[keys], lambda_info)
  }

  if (any(out$lambda_trimmed)) {
    wf_warn(
      sprintf("Trimmed %d data-driven lambda value(s).", sum(out$lambda_trimmed)),
      "wf_warning_quality",
      list(n = sum(out$lambda_trimmed))
    )
  }
  out
}

#' Warn for one-source fusion cells.
#'
#' @param cells Cell result table.
#' @keywords internal
#' @noRd
.wf_blend_warn_one_source <- function(cells) {
  n <- sum(cells$lambda_reason %in% c("online_only", "offline_only"))
  if (n > 0) {
    wf_warn(
      sprintf("%d fusion cell(s) are estimated from one source only.", n),
      "wf_warning_quality",
      list(n = n)
    )
  }
  invisible(n)
}

#' Build summary rows from fused cell estimates.
#'
#' @param cells Fused estimate cells.
#' @keywords internal
#' @noRd
.wf_blend_summary <- function(cells) {
  group_rows <- lapply(split(cells, cells$group), function(part) {
    valid <- is.finite(part$estimate) &
      is.finite(part$cell_weight) &
      part$cell_weight > 0
    estimate <- if (any(valid)) {
      sum(part$estimate[valid] * part$cell_weight[valid]) / sum(part$cell_weight[valid])
    } else {
      NA_real_
    }
    data.frame(
      group = part$group[[1]],
      estimate = estimate,
      cell_weight = sum(part$cell_weight[valid]),
      n_cells = nrow(part),
      stringsAsFactors = FALSE
    )
  })
  group_summary <- do.call(rbind, group_rows)
  rownames(group_summary) <- NULL

  valid <- is.finite(cells$estimate) &
    is.finite(cells$cell_weight) &
    cells$cell_weight > 0
  overall <- data.frame(
    group = "__overall__",
    estimate = if (any(valid)) {
      sum(cells$estimate[valid] * cells$cell_weight[valid]) / sum(cells$cell_weight[valid])
    } else {
      NA_real_
    },
    cell_weight = sum(cells$cell_weight[valid]),
    n_cells = nrow(cells),
    stringsAsFactors = FALSE
  )
  rbind(group_summary, overall)
}

#' Build global fixed-lambda sensitivity output.
#'
#' @param cells Fused estimate cells.
#' @keywords internal
#' @noRd
.wf_blend_sensitivity <- function(cells) {
  sweep_values <- seq(0.3, 0.9, by = 0.1)
  rows <- lapply(sweep_values, function(lambda_value) {
    tmp <- cells
    tmp$estimate <- lambda_value * tmp$estimate_online +
      (1 - lambda_value) * tmp$estimate_offline
    tmp$cell_weight <- lambda_value * tmp$weight_sum_online +
      (1 - lambda_value) * tmp$weight_sum_offline
    summary <- .wf_blend_summary(tmp)
    data.frame(
      lambda = lambda_value,
      summary,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Print a blend result.
#'
#' @param x A `wf_blend_result` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_blend_result <- function(x, ...) {
  n_cells <- if (!is.null(x$estimates) && nrow(x$estimates) > 0) {
    nrow(x$estimates)
  } else if (!is.null(x$cell_weights)) {
    nrow(x$cell_weights)
  } else {
    0L
  }
  lambda_range <- if (!is.null(x$lambda) && nrow(x$lambda) > 0) {
    sprintf("[%.4g, %.4g]", min(x$lambda$lambda), max(x$lambda$lambda))
  } else {
    "[NA, NA]"
  }
  warning_count <- sum(
    c(
      x$diagnostics$trimmed_lambda_count,
      x$diagnostics$one_source_cell_count
    ),
    na.rm = TRUE
  )
  cat(sprintf(
    "<wf_blend_result> %d cell(s); lambda %s; warnings: %d\n",
    n_cells,
    lambda_range,
    warning_count
  ))
  invisible(x)
}

#' Blend online and offline calibrated estimates
#'
#' Combines two `wf_weights` sources at the estimator level. Each source is
#' estimated within each fusion cell first; the source estimates are then
#' combined using the effective lambda recorded in the result.
#'
#' @param online Online-source `wf_weights`.
#' @param offline Offline-source `wf_weights`.
#' @param by_cell Character vector of cell columns.
#' @param lambda Lambda strategy: `"neff"`, `"inverse_variance"`, or `"fixed"`.
#' @param lambda_fixed Fixed lambda scalar or key table when `lambda = "fixed"`.
#' @param outcome Optional numeric outcome column.
#' @param level Lambda level: `"cell"` or `"group"`.
#' @param trim_lambda Two bounds used to clamp data-driven lambdas.
#' @param sensitivity Whether to compute a global-lambda sensitivity sweep.
#'
#' @return A `wf_blend_result` object.
#' @export
wf_blend <- function(online, offline, by_cell,
                     lambda = c("neff", "inverse_variance", "fixed"),
                     lambda_fixed = NULL,
                     outcome = NULL,
                     level = c("cell", "group"),
                     trim_lambda = c(0.05, 0.95),
                     sensitivity = TRUE) {
  t0 <- Sys.time()
  lambda <- .wf_blend_match(lambda, c("neff", "inverse_variance", "fixed"), "lambda")
  level <- .wf_blend_match(level, c("cell", "group"), "level")
  by_cell <- .wf_blend_by_cell(by_cell)
  trim_lambda <- .wf_blend_trim(trim_lambda)
  if (!is.null(outcome) && (length(outcome) != 1 || is.na(outcome) || !nzchar(outcome))) {
    wf_abort("`outcome` must be `NULL` or a single non-empty column name.", "wf_error_input")
  }
  sensitivity <- isTRUE(sensitivity)

  .wf_blend_check_source(online, "online", by_cell, outcome)
  .wf_blend_check_source(offline, "offline", by_cell, outcome)
  .wf_blend_check_fixed_required(lambda, lambda_fixed)

  online_cells <- .wf_blend_source_cells(online, "online", by_cell, outcome)
  offline_cells <- .wf_blend_source_cells(offline, "offline", by_cell, outcome)
  cells <- .wf_blend_merge_cells(online_cells, offline_cells, by_cell)

  lambda_table <- .wf_blend_lambda_for_level(
    online,
    offline,
    cells,
    by_cell,
    outcome,
    lambda,
    lambda_fixed,
    level,
    trim_lambda
  )
  cell_keys <- .wf_cell_key(as.matrix(cells[, c("group", by_cell), drop = FALSE]), c("group", by_cell))
  lambda_keys <- .wf_cell_key(as.matrix(lambda_table[, c("group", by_cell), drop = FALSE]), c("group", by_cell))
  cells <- cbind(cells, lambda_table[match(cell_keys, lambda_keys), c("lambda", "lambda_reason", "lambda_trimmed")])

  if (!is.null(outcome)) {
    cells$estimate <- cells$lambda * cells$estimate_online +
      (1 - cells$lambda) * cells$estimate_offline
    cells$variance <- (cells$lambda^2) * cells$variance_online +
      ((1 - cells$lambda)^2) * cells$variance_offline
    cells$cell_weight <- cells$lambda * cells$weight_sum_online +
      (1 - cells$lambda) * cells$weight_sum_offline
  }

  .wf_blend_warn_one_source(cells)

  if (!is.null(outcome)) {
    summary <- .wf_blend_summary(cells)
    sensitivity_out <- if (sensitivity) .wf_blend_sensitivity(cells) else NULL
    cell_weights <- NULL
  } else {
    cells$fused_cell_total <- cells$lambda * cells$weight_sum_online +
      (1 - cells$lambda) * cells$weight_sum_offline
    summary <- data.frame()
    sensitivity_out <- NULL
    cell_weights <- cells
  }

  out <- list(
    estimates = if (is.null(outcome)) data.frame() else cells,
    summary = summary,
    lambda = cells[c("group", by_cell, "lambda", "lambda_reason", "lambda_trimmed")],
    diagnostics = list(
      source_support = cells,
      trimmed_lambda_count = sum(cells$lambda_trimmed),
      one_source_cell_count = sum(cells$lambda_reason %in% c("online_only", "offline_only"))
    ),
    sensitivity = sensitivity_out,
    provenance = list(
      method = "blend",
      by_cell = by_cell,
      outcome = outcome,
      lambda = lambda,
      level = level,
      trim_lambda = trim_lambda,
      sources = list(
        online = online$provenance,
        offline = offline$provenance
      ),
      assumptions = c(
        "Convex fusion assumes both source estimates are approximately unbiased for the cell quantity.",
        "Online-source unbiasedness depends on calibration variables explaining the selection mechanism.",
        "Sensitivity output exposes dependence on lambda choices."
      ),
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_blend_package_version()
    )
  )
  if (!is.null(cell_weights)) {
    out$cell_weights <- cell_weights
  }
  structure(out, class = "wf_blend_result")
}
