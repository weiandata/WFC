#' Return the loaded package version for attrition provenance.
#'
#' @keywords internal
#' @noRd
.wf_attrition_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("WFC")),
    error = function(e) "0.15.0"
  )
}

#' Extract predictors from an attrition model formula.
#'
#' @param formula Formula supplied by the user.
#' @keywords internal
#' @noRd
.wf_attrition_predictors <- function(formula) {
  if (!inherits(formula, "formula") || !length(formula) %in% c(2, 3)) {
    wf_abort(
      "`formula` must be a one-sided or two-sided formula naming retention predictors.",
      "wf_error_input"
    )
  }
  rhs <- if (length(formula) == 3) formula[[3]] else formula[[2]]
  predictors <- all.vars(rhs)
  if (length(predictors) == 0) {
    wf_abort(
      "`formula` must name at least one retention predictor.",
      "wf_error_input"
    )
  }
  predictors
}

#' Resolve a logical retention flag.
#'
#' @param x Retention indicator vector.
#' @param retained Column name.
#' @keywords internal
#' @noRd
.wf_attrition_flag <- function(x, retained) {
  if (anyNA(x)) {
    wf_abort(
      sprintf("`%s` must not contain missing retention values.", retained),
      "wf_error_input",
      list(retained = retained)
    )
  }
  if (is.logical(x)) {
    keep <- x
  } else if (is.numeric(x) || is.integer(x)) {
    keep <- as.numeric(x) == 1
  } else {
    value <- tolower(.chr(x))
    if (!all(value %in% c("1", "0", "true", "false", "yes", "no", "retained", "lost", NA))) {
      wf_abort(
        sprintf(
          "`%s` must be logical, 0/1, or a recognized retained/lost label.",
          retained
        ),
        "wf_error_input",
        list(retained = retained)
      )
    }
    keep <- value %in% c("1", "true", "yes", "retained")
  }
  keep
}

#' Standardized mean difference for attrition balance.
#'
#' @param retained Retained-unit values.
#' @param full Full prior-wave values.
#' @param weights Retained-unit weights.
#' @keywords internal
#' @noRd
.wf_attrition_smd <- function(retained, full, weights) {
  sd_pool <- stats::sd(full)
  if (!is.finite(sd_pool) || sd_pool == 0) {
    sd_pool <- NA_real_
  }
  c(
    unweighted = (mean(retained) - mean(full)) / sd_pool,
    weighted = (stats::weighted.mean(retained, weights) - mean(full)) / sd_pool
  )
}

#' Build attrition balance diagnostics.
#'
#' @param panel Full panel frame.
#' @param keep Retention flag.
#' @param predictors Model predictors.
#' @param weights Retained-unit attrition weights.
#' @keywords internal
#' @noRd
.wf_attrition_balance <- function(panel, keep, predictors, weights) {
  rows <- list()
  retained <- panel[keep, , drop = FALSE]
  for (predictor in predictors) {
    x_retained <- retained[[predictor]]
    x_full <- panel[[predictor]]
    if (is.numeric(x_full)) {
      smd <- .wf_attrition_smd(x_retained, x_full, weights)
      rows[[length(rows) + 1L]] <- data.frame(
        variable = predictor,
        level = NA_character_,
        full_mean = mean(x_full),
        retained_mean_unweighted = mean(x_retained),
        retained_mean_weighted = stats::weighted.mean(x_retained, weights),
        smd_unweighted = unname(smd[["unweighted"]]),
        smd_weighted = unname(smd[["weighted"]]),
        stringsAsFactors = FALSE
      )
    } else {
      levels <- sort(unique(.chr(x_full)))
      for (level in levels[-1]) {
        full_dummy <- as.numeric(.chr(x_full) == level)
        retained_dummy <- as.numeric(.chr(x_retained) == level)
        smd <- .wf_attrition_smd(retained_dummy, full_dummy, weights)
        rows[[length(rows) + 1L]] <- data.frame(
          variable = predictor,
          level = level,
          full_mean = mean(full_dummy),
          retained_mean_unweighted = mean(retained_dummy),
          retained_mean_weighted = stats::weighted.mean(retained_dummy, weights),
          smd_unweighted = unname(smd[["unweighted"]]),
          smd_weighted = unname(smd[["weighted"]]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

#' Fit one attrition model group.
#'
#' @param panel Full group panel.
#' @param keep Retention flag for the group.
#' @param predictors Model predictors.
#' @param group Group label.
#' @keywords internal
#' @noRd
.wf_attrition_fit_group <- function(panel, keep, predictors, group) {
  if (sum(keep) == 0 || sum(!keep) == 0) {
    wf_abort(
      sprintf(
        "Group '%s' must contain both retained and lost units to fit attrition weights.",
        group
      ),
      "wf_error_overlap",
      list(group = group, retained = sum(keep), lost = sum(!keep))
    )
  }
  data <- panel
  data$.wf_retained <- as.integer(keep)
  formula <- stats::reformulate(predictors, response = ".wf_retained")
  fit <- stats::glm(formula, family = stats::binomial(), data = data)
  phat <- stats::fitted(fit)
  if (any(!is.finite(phat)) || any(phat <= 0 | phat >= 1)) {
    wf_warn(
      sprintf(
        "Group '%s': fitted retention probabilities touch 0 or 1; attrition weights may be unstable.",
        group
      ),
      "wf_warning_quality",
      list(group = group)
    )
  }
  pmax(pmin(phat, 1 - 1e-8), 1e-8)
}

#' Estimate panel attrition weights
#'
#' Models wave-to-wave retention in a panel and returns inverse-retention
#' weights for retained units. The result inherits from `wf_weights`, so it can
#' be composed with later calibration stages through [wf_compose()].
#'
#' @param panel Full prior-wave panel data.
#' @param retained Column indicating whether each prior-wave unit was retained
#'   into the next wave.
#' @param formula One-sided or two-sided formula naming retention predictors.
#' @param id Optional unique unit identifier column.
#' @param by Optional grouping column; separate retention models are fit by
#'   group.
#' @param stabilize Whether to multiply inverse probabilities by the group
#'   retention rate before normalization.
#' @param trim Optional positive scalar cap, applied as `trim * median(weight)`
#'   within each group before mean-one normalization.
#'
#' @return A `wf_attrition_weights` object inheriting from `wf_weights`, with a
#'   `$balance` diagnostic table and per-group retention log.
#' @export
wf_attrition <- function(panel, retained, formula, id = NULL, by = NULL,
                         stabilize = TRUE, trim = NULL) {
  t0 <- Sys.time()
  if (!is.data.frame(panel) || nrow(panel) == 0) {
    wf_abort("`panel` must be a non-empty data frame.", "wf_error_input")
  }
  if (!.wf_is_string(retained)) {
    wf_abort("`retained` must be one non-empty column name.", "wf_error_input")
  }
  .require_cols(panel, c(retained, id, by), "panel")
  predictors <- .wf_attrition_predictors(formula)
  .require_cols(panel, predictors, "panel")
  if (any(vapply(panel[predictors], function(x) anyNA(x), logical(1)))) {
    wf_abort(
      "Retention-model predictors must not contain missing values.",
      "wf_error_input"
    )
  }
  if (length(stabilize) != 1 || !is.logical(stabilize) || is.na(stabilize)) {
    wf_abort("`stabilize` must be TRUE or FALSE.", "wf_error_input")
  }
  if (!is.null(trim) &&
      (length(trim) != 1 || !is.numeric(trim) || !is.finite(trim) ||
       trim <= 0)) {
    wf_abort("`trim` must be NULL or one positive finite number.", "wf_error_input")
  }

  keep <- .wf_attrition_flag(panel[[retained]], retained)
  group <- if (is.null(by)) rep("_panel_", nrow(panel)) else .chr(panel[[by]])
  ids <- if (is.null(id)) as.character(seq_len(nrow(panel))) else .chr(panel[[id]])
  if (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids)) {
    wf_abort(
      "Attrition weighting requires non-missing unique unit IDs.",
      "wf_error_schema"
    )
  }

  rows <- list()
  logs <- list()
  balance <- list()
  probability <- rep(NA_real_, nrow(panel))
  for (group_name in unique(group)) {
    idx <- which(group == group_name)
    keep_g <- keep[idx]
    phat <- .wf_attrition_fit_group(
      panel[idx, , drop = FALSE],
      keep_g,
      predictors,
      group_name
    )
    probability[idx] <- phat
    raw <- 1 / phat[keep_g]
    if (stabilize) {
      raw <- mean(keep_g) * raw
    }
    trimmed <- 0L
    if (!is.null(trim)) {
      cap <- trim * stats::median(raw)
      hit <- raw > cap
      trimmed <- sum(hit)
      raw[hit] <- cap
    }
    weight <- raw / mean(raw)
    retained_idx <- idx[keep_g]
    rows[[group_name]] <- data.frame(
      id = ids[retained_idx],
      group = group_name,
      weight = weight,
      feature = 1 / weight,
      retention_probability = phat[keep_g],
      stringsAsFactors = FALSE
    )
    logs[[group_name]] <- data.frame(
      group = group_name,
      n = length(idx),
      retained = sum(keep_g),
      lost = sum(!keep_g),
      retention_rate = mean(keep_g),
      trimmed = trimmed,
      weight_min = min(weight),
      weight_max = max(weight),
      stringsAsFactors = FALSE
    )
    bal <- .wf_attrition_balance(
      panel[idx, , drop = FALSE],
      keep_g,
      predictors,
      weight
    )
    bal$group <- group_name
    balance[[group_name]] <- bal[c(
      "group", "variable", "level", "full_mean",
      "retained_mean_unweighted", "retained_mean_weighted",
      "smd_unweighted", "smd_weighted"
    )]
  }

  out <- structure(list(
    data = do.call(rbind, rows),
    log = do.call(rbind, logs),
    achieved = NULL,
    balance = do.call(rbind, balance),
    retention_probability = data.frame(
      id = ids,
      group = group,
      retained = keep,
      probability = probability,
      stringsAsFactors = FALSE
    ),
    provenance = list(
      method = "attrition",
      retained = retained,
      predictors = predictors,
      id = id,
      by = by,
      stabilize = stabilize,
      trim = trim,
      assumption = paste(
        "Inverse-retention weighting assumes retention is ignorable after",
        "conditioning on the model predictors."
      ),
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_attrition_package_version()
    )
  ), class = c("wf_attrition_weights", "wf_weights"))
  row.names(out$data) <- NULL
  row.names(out$log) <- NULL
  row.names(out$balance) <- NULL
  out
}

#' Print attrition weights
#'
#' @param x A `wf_attrition_weights` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_attrition_weights <- function(x, ...) {
  cat(sprintf(
    "<wf_attrition_weights> %d retained unit(s) in %d group(s)\n",
    nrow(x$data),
    nrow(x$log)
  ))
  cat(sprintf(
    "  retention range [%.3f, %.3f]; weight range [%.4g, %.4g]\n",
    min(x$retention_probability$probability),
    max(x$retention_probability$probability),
    min(x$data$weight),
    max(x$data$weight)
  ))
  invisible(x)
}
