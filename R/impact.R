#' Build one fixed descriptive impact row.
#'
#' @param outcome Outcome column name.
#' @param level_label Reported category level or `NA_character_` for a mean.
#' @param values Numeric analysis values.
#' @param weights Aligned locked weights.
#' @param confidence Confidence level.
#' @param proportion Whether `values` is a zero-one indicator.
#' @keywords internal
#' @noRd
.wf_impact_row <- function(outcome, level_label, values, weights,
                           confidence, proportion) {
  keep <- !is.na(values)
  values <- values[keep]
  weights <- weights[keep]
  if (!length(values)) {
    .wf_safety_abort(
      "outcome_all_missing",
      sprintf("Outcome '%s' has no non-missing values.", outcome),
      outcome
    )
  }

  unweighted <- mean(values)
  weighted <- sum(weights * values) / sum(weights)
  kish_ess <- sum(weights)^2 / sum(weights^2)
  if (proportion) {
    variance <- weighted * (1 - weighted)
  } else {
    variance <- sum(weights * (values - weighted)^2) / sum(weights)
  }
  se <- if (kish_ess > 1) sqrt(variance / kish_ess) else NA_real_
  z <- stats::qnorm((1 + confidence) / 2)
  conf_low <- weighted - z * se
  conf_high <- weighted + z * se
  if (proportion) {
    conf_low <- max(0, conf_low)
    conf_high <- min(1, conf_high)
  }

  data.frame(
    outcome = outcome,
    level = level_label,
    n = length(values),
    unweighted = unweighted,
    weighted = weighted,
    difference = weighted - unweighted,
    kish_ess = kish_ess,
    se = se,
    conf_low = conf_low,
    conf_high = conf_high,
    stringsAsFactors = FALSE
  )
}

#' Calculate the identity of a post-lock impact result.
#'
#' @param impact Impact fields.
#' @keywords internal
#' @noRd
.wf_impact_identity <- function(impact) {
  .wf_sha256_object(impact[setdiff(names(impact), c("created", "identity"))])
}

#' Assess descriptive outcome impact after weights are locked
#'
#' Compares fixed unweighted and locked-weight estimates. This function cannot
#' accept target values, selection callbacks, or planning controls, and it never
#' recalculates weights.
#'
#' @param weights An unchanged `wf_locked_weights` object.
#' @param data Analysis data frame with the exact locked unit-ID set.
#' @param id Unique identifier column in `data`.
#' @param outcomes Character vector naming outcome columns.
#' @param level Normal-approximation confidence level.
#'
#' @return A `wf_impact` object with fixed descriptive summaries.
#' @export
wf_assess_impact <- function(weights, data, id, outcomes, level = 0.95) {
  if (!inherits(weights, "wf_locked_weights") ||
      !identical(weights$identity, .wf_locked_weight_identity(weights))) {
    .wf_safety_abort(
      "locked_weights_invalid",
      "`weights` must be unchanged locked weights.",
      "weights"
    )
  }
  if (!is.data.frame(data)) {
    .wf_safety_abort(
      "analysis_data_invalid",
      "`data` must be a data frame.",
      "data"
    )
  }
  if (!is.character(outcomes) || !length(outcomes) || anyNA(outcomes) ||
      any(!nzchar(outcomes)) || anyDuplicated(outcomes)) {
    .wf_safety_abort(
      "outcomes_invalid",
      "`outcomes` must be unique, non-empty column names.",
      "outcomes"
    )
  }
  if (id %in% outcomes) {
    .wf_safety_abort(
      "outcome_is_identifier",
      "The identifier column cannot be assessed as an outcome.",
      "outcomes"
    )
  }
  .require_cols(data, outcomes, "analysis data")
  if (!is.numeric(level) || length(level) != 1L || is.na(level) ||
      !is.finite(level) || level <= 0.5 || level >= 1) {
    .wf_safety_abort(
      "impact_level_invalid",
      "`level` must be one number between 0.5 and 1.",
      "level"
    )
  }

  index <- .wf_match_unit_ids(
    data,
    id,
    weights$data$id,
    "locked weights",
    "wf_assess_impact()"
  )
  aligned_weights <- weights$data$weight[index]
  rows <- list()
  row_index <- 0L

  for (outcome in outcomes) {
    values <- data[[outcome]]
    if (inherits(values, c("Date", "POSIXt")) || is.list(values) ||
        is.matrix(values) || length(dim(values))) {
      .wf_safety_abort(
        "outcome_type_unsupported",
        sprintf("Outcome '%s' has an unsupported structured type.", outcome),
        outcome,
        next_actions = "supply_numeric_logical_or_factor_outcome"
      )
    }

    if (is.logical(values)) {
      row_index <- row_index + 1L
      rows[[row_index]] <- .wf_impact_row(
        outcome,
        "TRUE",
        as.numeric(values),
        aligned_weights,
        level,
        TRUE
      )
    } else if (is.factor(values)) {
      declared_levels <- levels(values)
      if (!length(declared_levels)) {
        .wf_safety_abort(
          "outcome_levels_missing",
          sprintf("Factor outcome '%s' has no declared levels.", outcome),
          outcome
        )
      }
      report_levels <- if (length(declared_levels) == 2L) {
        declared_levels[[2]]
      } else {
        declared_levels
      }
      for (category in report_levels) {
        row_index <- row_index + 1L
        indicator <- ifelse(is.na(values), NA_real_, as.numeric(values == category))
        rows[[row_index]] <- .wf_impact_row(
          outcome,
          category,
          indicator,
          aligned_weights,
          level,
          TRUE
        )
      }
    } else if (is.numeric(values)) {
      if (any(!is.finite(values[!is.na(values)]))) {
        .wf_safety_abort(
          "outcome_nonfinite",
          sprintf("Outcome '%s' contains non-finite values.", outcome),
          outcome
        )
      }
      observed <- unique(values[!is.na(values)])
      binary <- length(observed) <= 2L && all(observed %in% c(0, 1))
      row_index <- row_index + 1L
      rows[[row_index]] <- .wf_impact_row(
        outcome,
        if (binary) "1" else NA_character_,
        as.numeric(values),
        aligned_weights,
        level,
        binary
      )
    } else {
      .wf_safety_abort(
        "outcome_type_unsupported",
        sprintf(
          "Outcome '%s' must be numeric, logical, or a factor with declared levels.",
          outcome
        ),
        outcome,
        next_actions = "recode_outcome_explicitly"
      )
    }
  }

  impact <- list(
    summary = do.call(rbind, rows),
    weight_identity = weights$identity,
    outcomes = outcomes,
    level = level,
    created = .wf_iso_time(),
    package_version = .wf_package_version()
  )
  row.names(impact$summary) <- NULL
  impact$identity <- .wf_impact_identity(impact)
  class(impact) <- "wf_impact"
  impact
}

#' Print post-lock outcome impact
#'
#' @param x A `wf_impact` object.
#' @param ... Reserved for future use.
#'
#' @return `x`, invisibly.
#' @export
print.wf_impact <- function(x, ...) {
  cat("<wf_impact>\n")
  cat(" Locked weight identity: ", x$weight_identity, "\n", sep = "")
  cat(" Outcome rows: ", nrow(x$summary), "\n", sep = "")
  print(x$summary, row.names = FALSE)
  invisible(x)
}
