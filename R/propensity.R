#' Return the loaded package version for provenance.
#'
#' @keywords internal
#' @noRd
.wf_propensity_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("WFC")),
    error = function(e) "0.6.0"
  )
}

#' Standardized mean difference between online and reference for one covariate.
#'
#' @param x_on Numeric online values.
#' @param x_ref Numeric reference values.
#' @param w_on Online pseudo-weights (same length/order as `x_on`).
#' @keywords internal
#' @noRd
.wf_propensity_smd <- function(x_on, x_ref, w_on) {
  sd_pool <- sqrt((stats::var(x_on) + stats::var(x_ref)) / 2)
  if (!is.finite(sd_pool) || sd_pool == 0) sd_pool <- NA_real_
  c(
    unweighted = (mean(x_on) - mean(x_ref)) / sd_pool,
    weighted = (stats::weighted.mean(x_on, w_on) - mean(x_ref)) / sd_pool
  )
}

#' Build the online-vs-reference covariate balance table.
#'
#' @param stacked The stacked online+reference frame.
#' @param is_online Logical index of online rows in `stacked`.
#' @param predictors Predictor names.
#' @param w_on Online pseudo-weights (online-row order).
#' @keywords internal
#' @noRd
.wf_propensity_balance <- function(stacked, is_online, predictors, w_on) {
  online_rows <- stacked[is_online, , drop = FALSE]
  ref_rows <- stacked[!is_online, , drop = FALSE]
  rows <- list()
  for (p in predictors) {
    xo <- online_rows[[p]]
    xr <- ref_rows[[p]]
    if (is.numeric(xo)) {
      s <- .wf_propensity_smd(xo, xr, w_on)
      rows[[length(rows) + 1]] <- data.frame(
        variable = p, level = NA_character_,
        smd_unweighted = unname(s["unweighted"]),
        smd_weighted = unname(s["weighted"]),
        stringsAsFactors = FALSE
      )
    } else {
      levs <- sort(unique(.chr(c(xo, xr))))
      for (lv in levs[-1]) {
        s <- .wf_propensity_smd(
          as.numeric(.chr(xo) == lv),
          as.numeric(.chr(xr) == lv),
          w_on
        )
        rows[[length(rows) + 1]] <- data.frame(
          variable = p, level = lv,
          smd_unweighted = unname(s["unweighted"]),
          smd_weighted = unname(s["weighted"]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Build a propensity target: stacked reference frame and membership model spec.
#'
#' Stacks a self-selected `online` sample and a probability `reference` sample
#' into one frame with a membership indicator, so the online sample's selection
#' propensity can be modelled. No model is fit here; execution happens in
#' [wf_propensity()].
#'
#' @param online Data frame: the self-selected (non-probability) sample.
#' @param reference Data frame: the probability reference sample.
#' @param formula Two-sided membership formula, e.g. `member ~ age + edu`. The
#'   right-hand side names the model predictors; the left-hand side names the
#'   membership indicator the constructor creates (`1` online, `0` reference).
#' @param method Fit backend. Only `"logit"` is executable in this release;
#'   `"rf"` / `"gbm"` are reserved and abort in [wf_propensity()].
#' @param by Optional grouping column present in both frames; the propensity
#'   model is fit within each group.
#' @param id Optional id column in `online`; when `NULL`, online units are
#'   identified by row order.
#' @return A `wf_target_propensity` object.
#' @export
wf_target_propensity <- function(online, reference, formula,
                                 method = c("logit", "rf", "gbm"),
                                 by = NULL, id = NULL) {
  method <- match.arg(method)
  if (!is.data.frame(online) || nrow(online) == 0) {
    wf_abort("`online` must be a non-empty data frame.", "wf_error_input")
  }
  if (!is.data.frame(reference) || nrow(reference) == 0) {
    wf_abort("`reference` must be a non-empty data frame.", "wf_error_input")
  }
  if (!inherits(formula, "formula") || length(formula) != 3) {
    wf_abort(
      "`formula` must be a two-sided formula, e.g. member ~ age + edu.",
      "wf_error_input"
    )
  }
  membership <- all.vars(formula[[2]])
  if (length(membership) != 1) {
    wf_abort(
      "The left-hand side of `formula` must be a single membership name.",
      "wf_error_input"
    )
  }
  predictors <- all.vars(formula[[3]])
  if (length(predictors) == 0) {
    wf_abort(
      "`formula` must name at least one predictor on the right-hand side.",
      "wf_error_input"
    )
  }
  if (membership %in% predictors) {
    wf_abort(
      sprintf("Membership name '%s' collides with a predictor.", membership),
      "wf_error_input", list(membership = membership)
    )
  }
  miss_online <- setdiff(predictors, names(online))
  if (length(miss_online) > 0) {
    wf_abort(
      sprintf("`online` is missing predictor(s): %s",
              paste(miss_online, collapse = ", ")),
      "wf_error_input", list(missing = miss_online)
    )
  }
  miss_ref <- setdiff(predictors, names(reference))
  if (length(miss_ref) > 0) {
    wf_abort(
      sprintf("`reference` is missing predictor(s): %s",
              paste(miss_ref, collapse = ", ")),
      "wf_error_input", list(missing = miss_ref)
    )
  }
  if (!is.null(by)) {
    if (length(by) != 1 || !is.character(by)) {
      wf_abort("`by` must be a single column name.", "wf_error_input")
    }
    if (!by %in% names(online)) {
      wf_abort(sprintf("`online` is missing `by` column '%s'.", by),
               "wf_error_input", list(by = by))
    }
    if (!by %in% names(reference)) {
      wf_abort(sprintf("`reference` is missing `by` column '%s'.", by),
               "wf_error_input", list(by = by))
    }
  }
  if (!is.null(id)) {
    if (length(id) != 1 || !is.character(id)) {
      wf_abort("`id` must be a single column name.", "wf_error_input")
    }
    if (!id %in% names(online)) {
      wf_abort(sprintf("`online` is missing `id` column '%s'.", id),
               "wf_error_input", list(id = id))
    }
  }

  keep <- unique(c(predictors, by))
  online_part <- online[, keep, drop = FALSE]
  online_part[[membership]] <- 1L
  online_part$.wf_source <- "online"
  ref_part <- reference[, keep, drop = FALSE]
  ref_part[[membership]] <- 0L
  ref_part$.wf_source <- "reference"
  stacked <- rbind(online_part, ref_part)

  online_ids <- if (is.null(id)) {
    as.character(seq_len(nrow(online)))
  } else {
    .chr(online[[id]])
  }

  structure(list(
    online = online,
    reference = reference,
    stacked = stacked,
    membership = membership,
    predictors = predictors,
    formula = formula,
    method = method,
    by = by,
    id = id,
    online_ids = online_ids,
    n_online = nrow(online),
    n_reference = nrow(reference),
    provenance = list(
      created = Sys.time(),
      package_version = .wf_propensity_package_version()
    )
  ), class = "wf_target_propensity")
}

#' Correct a non-probability sample by inverse-propensity pseudo-weighting.
#'
#' Fits the membership model declared in a [wf_target_propensity()] object and
#' converts each online unit's fitted membership probability into a pseudo-design
#' weight. The result is a `wf_weights` object suitable as an `init_weight` for
#' [wf_rake()] / [wf_poststrat()] and as a stage in [wf_compose()].
#'
#' @param target A `wf_target_propensity` object.
#' @param weight Pseudo-weight form. Only `"ipw"` is executable in this release;
#'   `"kernel"` / `"matching"` are reserved.
#' @param stabilize Use stabilized IPW (`pi_bar / phat`) to tame extreme weights.
#' @param trim Optional positive scalar: clamp weights above `trim * median(w)`.
#' @return A `wf_propensity_weights` object inheriting from `wf_weights`, with
#'   `$overlap` and `$balance` diagnostics.
#' @export
wf_propensity <- function(target,
                          weight = c("ipw", "kernel", "matching"),
                          stabilize = TRUE, trim = NULL) {
  if (!inherits(target, "wf_target_propensity")) {
    wf_abort("`target` must be a wf_target_propensity object.", "wf_error_input")
  }
  weight <- match.arg(weight)
  if (weight != "ipw") {
    wf_abort(
      sprintf("weight = '%s' is not yet supported; only 'ipw' is implemented in this release.",
              weight),
      "wf_error_input", list(weight = weight)
    )
  }
  if (target$method != "logit") {
    wf_abort(
      sprintf("method = '%s' is not yet supported; only 'logit' is implemented in this release.",
              target$method),
      "wf_error_input", list(method = target$method)
    )
  }
  if (!is.null(trim) &&
      (length(trim) != 1 || !is.finite(trim) || trim <= 0)) {
    wf_abort("`trim` must be a single positive number or NULL.",
             "wf_error_input", list(trim = trim))
  }
  t0 <- Sys.time()

  stacked <- target$stacked
  membership <- target$membership
  by <- target$by
  fml <- stats::reformulate(target$predictors, response = membership)

  na_rows <- Reduce(
    `|`,
    lapply(target$predictors, function(p) is.na(stacked[[p]]))
  )
  if (any(na_rows)) {
    wf_abort(sprintf(
      "%d of %d stacked row(s) (%.1f%%) have NA in membership-model predictor(s). Clean or impute these values before fitting the propensity model.",
      sum(na_rows),
      nrow(stacked),
      100 * sum(na_rows) / nrow(stacked)
    ), "wf_error_input", list(n = sum(na_rows)))
  }

  grp <- if (is.null(by)) rep(".all", nrow(stacked)) else .chr(stacked[[by]])
  is_online <- stacked$.wf_source == "online"

  phat <- rep(NA_real_, nrow(stacked))
  for (g in unique(grp)) {
    sel <- grp == g
    n_on <- sum(sel & is_online)
    n_ref <- sum(sel & !is_online)
    if (n_on == 0 || n_ref == 0) {
      wf_abort(
        sprintf("Group '%s' is missing an entire source (online: %d, reference: %d).",
                g, n_on, n_ref),
        "wf_error_overlap",
        list(group = g, n_online = n_on, n_reference = n_ref)
      )
    }
    fit <- stats::glm(fml, family = stats::binomial(),
                      data = stacked[sel, , drop = FALSE])
    phat[sel] <- stats::fitted(fit)
  }

  p_on <- phat[is_online]
  grp_on <- grp[is_online]

  raw <- 1 / p_on
  if (stabilize) {
    pibar <- tapply(stacked[[membership]], grp, mean)
    raw <- as.numeric(pibar[grp_on]) / p_on
  }

  trimmed <- 0L
  if (!is.null(trim)) {
    cap <- trim * stats::median(raw)
    hits <- raw > cap
    trimmed <- sum(hits)
    raw[hits] <- cap
  }

  w <- raw
  for (g in unique(grp_on)) {
    sel <- grp_on == g
    w[sel] <- w[sel] / mean(w[sel])
  }

  data <- data.frame(
    id = target$online_ids,
    group = grp_on,
    weight = w,
    feature = 1 / w,
    stringsAsFactors = FALSE
  )

  log <- data.frame(
    group = unique(grp_on),
    n = as.integer(table(grp_on)[unique(grp_on)]),
    stringsAsFactors = FALSE
  )

  boundary <- 0.99
  probs <- c(0, 0.01, 0.25, 0.5, 0.75, 0.99, 1)
  p_ref <- phat[!is_online]
  n_boundary <- sum(p_on > boundary)
  overlap <- list(
    threshold = boundary,
    online = stats::quantile(p_on, probs, names = TRUE),
    reference = stats::quantile(p_ref, probs, names = TRUE),
    online_values = unname(p_on),
    reference_values = unname(p_ref),
    n_boundary = n_boundary,
    n_online = length(p_on)
  )
  if (n_boundary > 0) {
    wf_warn(
      sprintf(
        "%d online unit(s) have propensity > %.2f (poor common support; extreme pseudo-weights).",
        n_boundary, boundary
      ),
      "wf_warning_quality",
      list(n_boundary = n_boundary, threshold = boundary)
    )
  }

  balance <- .wf_propensity_balance(stacked, is_online, target$predictors, w)

  structure(list(
    data = data,
    log = log,
    achieved = NULL,
    overlap = overlap,
    balance = balance,
    provenance = list(
      method = "propensity",
      fit_method = target$method,
      weight = weight,
      stabilize = stabilize,
      trim = trim,
      trimmed = trimmed,
      by = by,
      id = target$id,
      predictors = target$predictors,
      assumption = paste(
        "Inverse-propensity correction is unbiased only if the model",
        "covariates capture the full online selection mechanism."
      ),
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_propensity_package_version()
    )
  ), class = c("wf_propensity_weights", "wf_weights"))
}
