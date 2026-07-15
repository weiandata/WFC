#' Return the loaded package version for provenance.
#'
#' @keywords internal
#' @noRd
.wf_lincal_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("WFC")),
    error = function(e) "0.8.0"
  )
}

#' Build a calibration distance object (weight-generating function and slope).
#'
#' @param distance "linear" (GREG), "logit" (bounded), or "entropy".
#' @param bounds Two-element `c(L, U)` for logit; ignored for linear.
#' @keywords internal
#' @noRd
.wf_lincal_dist <- function(distance, bounds) {
  if (distance == "linear") {
    return(list(
      F = function(u) 1 + u,
      Fp = function(u) rep(1, length(u))
    ))
  }
  if (distance == "entropy") {
    return(list(
      F = function(u) exp(pmax(pmin(u, 700), -700)),
      Fp = function(u) exp(pmax(pmin(u, 700), -700))
    ))
  }
  L <- bounds[1]
  U <- bounds[2]
  A <- (U - L) / ((1 - L) * (U - 1))
  # Overflow-safe: for A*u >= 0 divide through by e = exp(A*u) so exp only ever
  # sees non-positive arguments (avoids Inf/Inf -> NaN when u overshoots).
  list(
    F = function(u) {
      s <- A * u
      out <- numeric(length(s))
      pos <- s >= 0
      em <- exp(-s[pos])
      out[pos] <- (L * (U - 1) * em + U * (1 - L)) / ((U - 1) * em + (1 - L))
      e <- exp(s[!pos])
      out[!pos] <- (L * (U - 1) + U * (1 - L) * e) / ((U - 1) + (1 - L) * e)
      out
    },
    Fp = function(u) {
      s <- A * u
      out <- numeric(length(s))
      pos <- s >= 0
      em <- exp(-s[pos])
      out[pos] <- (U - L)^2 * em / ((U - 1) * em + (1 - L))^2
      e <- exp(s[!pos])
      out[!pos] <- (U - L)^2 * e / ((U - 1) + (1 - L) * e)^2
      out
    }
  )
}

#' Build the calibration constraint matrix and target vector for one group.
#'
#' @param sub Group's (complete-case) sample subset.
#' @param dvars Calibration dimension names.
#' @param gr A target group: `list(total, margins)`.
#' @keywords internal
#' @noRd
.wf_lincal_build <- function(sub, dvars, gr) {
  n <- nrow(sub)
  cols <- list(rep(1, n))
  t <- gr$total
  labels <- data.frame(
    dim = "_total_",
    category = NA_character_,
    target = gr$total,
    stringsAsFactors = FALSE
  )
  for (d in dvars) {
    lev <- names(gr$margins[[d]])
    for (l in lev[-1]) {   # drop the first level as the reference
      cols[[length(cols) + 1]] <- as.numeric(.chr(sub[[d]]) == l)
      t <- c(t, gr$margins[[d]][[l]])
      labels <- rbind(
        labels,
        data.frame(
          dim = d,
          category = l,
          target = gr$margins[[d]][[l]],
          stringsAsFactors = FALSE
        )
      )
    }
  }
  list(X = do.call(cbind, cols), t = t, labels = labels)
}

#' Build full margin constraints for soft calibration.
#'
#' @param sub Group sample subset.
#' @param dvars Calibration dimension names.
#' @param gr A target group.
#' @keywords internal
#' @noRd
.wf_soft_build <- function(sub, dvars, gr) {
  n <- nrow(sub)
  cols <- list(rep(1, n))
  t <- gr$total
  labels <- data.frame(
    dim = "_total_",
    category = NA_character_,
    target = gr$total,
    stringsAsFactors = FALSE
  )
  for (d in dvars) {
    lev <- names(gr$margins[[d]])
    for (l in lev) {
      cols[[length(cols) + 1]] <- as.numeric(.chr(sub[[d]]) == l)
      t <- c(t, gr$margins[[d]][[l]])
      labels <- rbind(
        labels,
        data.frame(
          dim = d,
          category = l,
          target = gr$margins[[d]][[l]],
          stringsAsFactors = FALSE
        )
      )
    }
  }
  list(X = do.call(cbind, cols), t = t, labels = labels)
}

#' Resolve soft-calibration tolerances by dimension.
#'
#' @param tolerance Scalar or named vector.
#' @param dvars Calibration dimension names.
#' @keywords internal
#' @noRd
.wf_soft_tolerance <- function(tolerance, dvars) {
  if (!is.numeric(tolerance) || length(tolerance) == 0 ||
      anyNA(tolerance) || any(!is.finite(tolerance)) ||
      any(tolerance <= 0)) {
    wf_abort(
      "`tolerance` must be a positive finite number or a named positive vector by dimension.",
      "wf_error_input",
      list(tolerance = tolerance)
    )
  }
  if (length(tolerance) == 1 && is.null(names(tolerance))) {
    return(stats::setNames(rep(tolerance, length(dvars)), dvars))
  }
  if (is.null(names(tolerance)) || any(!nzchar(names(tolerance)))) {
    wf_abort(
      "Named `tolerance` values must name target dimensions.",
      "wf_error_input",
      list(tolerance = tolerance)
    )
  }
  missing <- setdiff(dvars, names(tolerance))
  extra <- setdiff(names(tolerance), dvars)
  if (length(missing) > 0 || length(extra) > 0) {
    wf_abort(
      sprintf(
        "`tolerance` must name every target dimension. Missing: %s; extra: %s.",
        paste(missing, collapse = ", "),
        paste(extra, collapse = ", ")
      ),
      "wf_error_schema",
      list(missing = missing, extra = extra)
    )
  }
  tolerance[dvars]
}

#' Build absolute tolerances for one soft-calibration group.
#'
#' @param labels Constraint labels.
#' @param tolerance_by_dim Named relative tolerances.
#' @param total Group total.
#' @keywords internal
#' @noRd
.wf_soft_constraint_tolerance <- function(labels, tolerance_by_dim, total) {
  out <- numeric(nrow(labels))
  for (i in seq_len(nrow(labels))) {
    if (labels$dim[[i]] == "_total_") {
      out[[i]] <- 0
    } else {
      out[[i]] <- tolerance_by_dim[[labels$dim[[i]]]] * total
    }
  }
  out
}

#' Solve one soft-calibration group.
#'
#' @param X Full constraint matrix.
#' @param d Base weights.
#' @param t Constraint target totals.
#' @param tolerance_abs Absolute per-constraint tolerances.
#' @param max_outer Maximum penalty-shrink rounds.
#' @param total Group total.
#' @param g Group label.
#' @keywords internal
#' @noRd
.wf_soft_group <- function(X, d, t, tolerance_abs, max_outer, total, g) {
  if (length(d) == 0 || any(!is.finite(d)) || any(d < 0) || sum(d) <= 0) {
    wf_abort(
      sprintf("Group '%s': base weights must be non-negative with positive total.", g),
      "wf_error_input",
      list(group = g)
    )
  }
  p <- ncol(X)
  phi <- ifelse(
    tolerance_abs > 0,
    pmax((tolerance_abs)^2, (.Machine$double.eps * total)^2),
    0
  )
  XtDX <- crossprod(X, X * d)
  residual0 <- t - as.numeric(crossprod(X, d))
  w <- d
  gap <- residual0
  iterations <- 0L

  for (outer in seq_len(max_outer)) {
    iterations <- outer
    system <- XtDX + diag(phi, p)
    step <- tryCatch(solve(system, residual0), error = function(e) NULL)
    if (is.null(step)) {
      wf_abort(
        sprintf("Group '%s': singular soft-calibration system.", g),
        "wf_error_feasibility",
        list(group = g)
      )
    }
    w <- d + d * as.numeric(X %*% step)
    gap <- t - as.numeric(crossprod(X, w))
    over <- abs(gap) > tolerance_abs + 1e-10 * max(total, 1) &
      tolerance_abs > 0
    if (!any(over)) {
      break
    }
    phi[over] <- phi[over] *
      pmax(0.05, pmin(0.5, tolerance_abs[over] / abs(gap[over])))
  }

  converged <- all(abs(gap) <= tolerance_abs + 1e-8 * max(total, 1))
  if (!converged) {
    wf_abort(
      sprintf(
        "Group '%s': soft calibration could not keep all relaxed margins within the declared tolerance.",
        g
      ),
      "wf_error_feasibility",
      list(group = g, max_gap = max(abs(gap) / total))
    )
  }
  if (any(!is.finite(w)) || any(w <= 0)) {
    wf_abort(
      sprintf(
        "Group '%s': soft calibration produced non-positive weights. Increase `tolerance` or use bounded logit calibration.",
        g
      ),
      "wf_error_feasibility",
      list(group = g)
    )
  }
  list(
    w = w,
    iterations = iterations,
    converged = converged,
    gap = gap,
    max_rel_gap = max(abs(gap)) / total,
    ratio = w / d
  )
}

#' Solve the calibration equations for one group by Newton iteration.
#'
#' @param X Constraint matrix (n x p).
#' @param d Base weights (length n).
#' @param t Target totals (length p; `t[1]` is the group total).
#' @param dist A `.wf_lincal_dist()` object.
#' @param tol Convergence tolerance on the max residual relative to `total`.
#' @param max_iter Iteration cap.
#' @param total Group total (for the relative residual).
#' @param g Group label (for error messages).
#' @keywords internal
#' @noRd
.wf_lincal_group <- function(X, d, t, dist, tol, max_iter, total, g) {
  lambda <- rep(0, ncol(X))
  u <- as.numeric(X %*% lambda)
  w <- d * dist$F(u)
  steps <- 0L
  converged <- FALSE
  maxr <- NA_real_
  repeat {
    resid <- t - as.numeric(t(X) %*% w)
    maxr <- max(abs(resid)) / total
    if (is.finite(maxr) && maxr < tol) {
      converged <- TRUE
      break
    }
    if (steps >= max_iter) break
    jac <- t(X) %*% (X * (d * dist$Fp(u)))
    step <- tryCatch(solve(jac, resid), error = function(e) NULL)
    if (is.null(step)) {
      wf_abort(
        sprintf("Group '%s': singular calibration system (empty category or collinear margins).", g),
        "wf_error_feasibility", list(group = g)
      )
    }
    # Damped Newton: shrink the step until weights stay finite and the residual
    # decreases (keeps the logit distance from overflowing on an overshoot).
    alpha <- 1
    repeat {
      lambda_try <- lambda + alpha * step
      u_try <- as.numeric(X %*% lambda_try)
      w_try <- d * dist$F(u_try)
      maxr_try <- max(abs(t - as.numeric(t(X) %*% w_try))) / total
      if (all(is.finite(w_try)) && is.finite(maxr_try) && maxr_try < maxr) break
      alpha <- alpha / 2
      if (alpha < 1e-10) break
    }
    lambda <- lambda + alpha * step
    steps <- steps + 1L
    u <- as.numeric(X %*% lambda)
    w <- d * dist$F(u)
  }
  if (!converged) {
    wf_abort(
      sprintf("Group '%s': calibration did not converge in %d iterations (max relative residual %.3g). Bounds may be too tight to meet the margins.",
              g, max_iter, maxr),
      "wf_error_feasibility", list(group = g, residual = maxr)
    )
  }
  list(w = w, iterations = steps, converged = TRUE,
       max_resid = maxr, ratio = dist$F(u))
}

#' Calibrate weights by a linear or logit distance (engine behind wf_calibrate).
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param distance "linear" or "logit".
#' @param method Reported method label ("greg" or "logit").
#' @param bounds `c(L, U)` for logit.
#' @param init_weight Optional base-weight column.
#' @param na "drop" or "error".
#' @param id Optional id column.
#' @param tol Convergence tolerance.
#' @param max_iter Iteration cap.
#' @param precheck Run `wf_precheck()` first.
#' @keywords internal
#' @noRd
.wf_lincalibrate <- function(sample, target, distance, method,
                             bounds = NULL, init_weight = NULL,
                             na = c("drop", "error"), id = NULL,
                             tol = 1e-8, max_iter = 100, precheck = TRUE) {
  na <- match.arg(na)
  t0 <- Sys.time()

  if (precheck) {
    pc <- wf_precheck(sample, target, id = id, na = "drop")
    if (!pc$ok) {
      wf_abort(sprintf(
        "Precheck reports %d blocking issue(s). Inspect wf_precheck(sample, target) before calibrating.",
        sum(pc$issues$severity == "error")
      ), "wf_error_feasibility", list(precheck = pc))
    }
  }

  dvars <- target$dims
  for (d in dvars) {
    if (!d %in% names(sample)) {
      wf_abort(sprintf("Calibration dimension '%s' not found in sample.", d),
               "wf_error_schema", list(dim = d))
    }
  }
  na_vars <- dvars
  na_table <- sapply(na_vars, function(d) is.na(sample[[d]]))
  if (is.null(dim(na_table))) {
    na_table <- matrix(na_table, nrow = nrow(sample))
  }
  na_mask <- rowSums(na_table) > 0
  if (any(na_mask)) {
    if (na == "error") {
      wf_abort(sprintf("%d row(s) have NA in calibration dimensions.", sum(na_mask)),
               "wf_error_schema", list(n = sum(na_mask)))
    }
    wf_warn(sprintf("na='drop': removed %d row(s) with NA in calibration dimensions.",
                    sum(na_mask)), "wf_warning_data")
    sample <- sample[!na_mask, , drop = FALSE]
  }

  if (is.null(init_weight)) {
    iw <- NULL   # per-group default (total/n) computed in the loop
  } else {
    if (length(init_weight) != 1 || !is.character(init_weight) ||
        !init_weight %in% names(sample)) {
      wf_abort(sprintf("init_weight column '%s' not found in sample.",
                       as.character(init_weight)[1]),
               "wf_error_schema", list(init_weight = init_weight))
    }
    iw <- as.numeric(sample[[init_weight]])
    if (any(!is.finite(iw)) || any(iw < 0)) {
      wf_abort("init_weight must be non-negative and finite.",
               "wf_error_input", list(init_weight = init_weight))
    }
  }

  dist <- .wf_lincal_dist(distance, bounds)
  gkey <- .wf_group_keys(sample, target$by)
  ids <- if (is.null(id)) seq_len(nrow(sample)) else sample[[id]]

  res_rows <- list()
  logs <- list()
  achieved <- list()
  for (g in intersect(names(target$groups), unique(gkey))) {
    sel <- which(gkey == g)
    gr <- target$groups[[g]]
    sub <- sample[sel, , drop = FALSE]
    built <- .wf_lincal_build(sub, dvars, gr)
    d_g <- if (is.null(iw)) rep(gr$total / length(sel), length(sel)) else iw[sel]
    fit <- .wf_lincal_group(built$X, d_g, built$t, dist,
                            tol, max_iter, gr$total, g)

    res_rows[[g]] <- data.frame(
      id = .chr(ids[sel]),
      group = g,
      weight = fit$w,
      feature = 1 / fit$w,
      stringsAsFactors = FALSE
    )
    logs[[g]] <- data.frame(
      group = g, n = length(sel), iterations = fit$iterations,
      converged = fit$converged, max_resid = fit$max_resid,
      ratio_min = min(fit$ratio), ratio_max = max(fit$ratio),
      kl_divergence = if (distance == "entropy") {
        sum(fit$w * log(fit$w / d_g)) / sum(fit$w)
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
    achieved[[g]] <- lapply(dvars, function(d) {
      levs <- names(gr$margins[[d]])
      stats::setNames(
        vapply(levs, function(l) sum(fit$w[.chr(sub[[d]]) == l]), numeric(1)),
        levs
      )
    })
    names(achieved[[g]]) <- dvars
  }

  out <- structure(list(
    data = do.call(rbind, res_rows),
    log = do.call(rbind, logs),
    achieved = achieved,
    provenance = list(
      method = method,
      distance = distance,
      bounds = bounds,
      init_weight = init_weight,
      na = na,
      dims = dvars,
      by = target$by,
      tol = tol,
      max_iter = max_iter,
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_lincal_package_version()
    )
  ), class = "wf_weights")
  out
}

#' Calibrate weights with soft bounded margin relaxation.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param tolerance Positive scalar or named vector by dimension. Values are
#'   interpreted as fractions of each group total.
#' @param init_weight Optional base-weight column.
#' @param na "drop" or "error".
#' @param id Optional id column.
#' @param max_outer Maximum penalty adjustment rounds.
#' @param precheck Run a soft-aware precheck first.
#' @keywords internal
#' @noRd
.wf_softcalibrate <- function(sample, target, tolerance = 0.02,
                              init_weight = NULL,
                              na = c("drop", "error"), id = NULL,
                              max_outer = 25, precheck = TRUE) {
  na <- match.arg(na)
  t0 <- Sys.time()
  if (!inherits(target, "wf_target")) {
    wf_abort("`target` must be a wf_target object.", "wf_error_input")
  }
  if (!is.data.frame(sample) || nrow(sample) == 0) {
    wf_abort("`sample` must be a non-empty data frame.", "wf_error_input")
  }
  if (length(max_outer) != 1 || !is.numeric(max_outer) ||
      !is.finite(max_outer) || max_outer < 1 ||
      max_outer != as.integer(max_outer)) {
    wf_abort("`max_outer` must be a positive integer.", "wf_error_input")
  }

  dvars <- target$dims
  tolerance_by_dim <- .wf_soft_tolerance(tolerance, dvars)
  .require_cols(sample, c(id, target$by, dvars), "sample")

  if (precheck) {
    pc <- wf_precheck(sample, target, id = id, na = na)
    blocking <- pc$issues[
      pc$issues$severity == "error" & pc$issues$check != "cat_infeasible",
      ,
      drop = FALSE
    ]
    if (nrow(blocking) > 0) {
      wf_abort(
        sprintf(
          "Soft calibration precheck found %d non-relaxable blocking issue(s).",
          nrow(blocking)
        ),
        "wf_error_feasibility",
        list(precheck = pc, blocking = blocking)
      )
    }
  }

  na_table <- sapply(dvars, function(d) is.na(sample[[d]]))
  if (is.null(dim(na_table))) {
    na_table <- matrix(na_table, nrow = nrow(sample))
  }
  na_mask <- rowSums(na_table) > 0
  if (any(na_mask)) {
    if (na == "error") {
      wf_abort(
        sprintf("%d row(s) have NA in calibration dimensions.", sum(na_mask)),
        "wf_error_schema",
        list(n = sum(na_mask))
      )
    }
    wf_warn(
      sprintf(
        "na='drop': removed %d row(s) with NA in calibration dimensions.",
        sum(na_mask)
      ),
      "wf_warning_data"
    )
    sample <- sample[!na_mask, , drop = FALSE]
  }

  if (is.null(init_weight)) {
    iw <- NULL
  } else {
    if (length(init_weight) != 1 || !is.character(init_weight) ||
        !init_weight %in% names(sample)) {
      wf_abort(
        sprintf("init_weight column '%s' not found in sample.",
                as.character(init_weight)[1]),
        "wf_error_schema",
        list(init_weight = init_weight)
      )
    }
    iw <- as.numeric(sample[[init_weight]])
    if (any(!is.finite(iw)) || any(iw < 0)) {
      wf_abort(
        "init_weight must be non-negative and finite.",
        "wf_error_input",
        list(init_weight = init_weight)
      )
    }
  }

  gkey <- .wf_group_keys(sample, target$by)
  ids <- if (is.null(id)) seq_len(nrow(sample)) else sample[[id]]
  res_rows <- list()
  logs <- list()
  achieved <- list()
  relaxation <- list()

  for (g in intersect(names(target$groups), unique(gkey))) {
    sel <- which(gkey == g)
    gr <- target$groups[[g]]
    sub <- sample[sel, , drop = FALSE]
    built <- .wf_soft_build(sub, dvars, gr)
    d_g <- if (is.null(iw)) rep(gr$total / length(sel), length(sel)) else iw[sel]
    tolerance_abs <- .wf_soft_constraint_tolerance(
      built$labels,
      tolerance_by_dim,
      gr$total
    )
    fit <- .wf_soft_group(
      built$X,
      d_g,
      built$t,
      tolerance_abs,
      as.integer(max_outer),
      gr$total,
      g
    )

    res_rows[[g]] <- data.frame(
      id = .chr(ids[sel]),
      group = g,
      weight = fit$w,
      feature = 1 / fit$w,
      stringsAsFactors = FALSE
    )
    logs[[g]] <- data.frame(
      group = g,
      n = length(sel),
      iterations = fit$iterations,
      converged = fit$converged,
      max_rel_gap = fit$max_rel_gap,
      n_relaxed = sum(abs(fit$gap) > 1e-9 & tolerance_abs > 0),
      ratio_min = min(fit$ratio),
      ratio_max = max(fit$ratio),
      stringsAsFactors = FALSE
    )
    achieved[[g]] <- lapply(dvars, function(d) {
      levs <- names(gr$margins[[d]])
      stats::setNames(
        vapply(levs, function(l) sum(fit$w[.chr(sub[[d]]) == l]), numeric(1)),
        levs
      )
    })
    names(achieved[[g]]) <- dvars
    achieved_constraint <- as.numeric(crossprod(built$X, fit$w))
    relaxation[[g]] <- data.frame(
      group = g,
      dim = built$labels$dim,
      category = built$labels$category,
      target = built$t,
      achieved = achieved_constraint,
      gap = built$t - achieved_constraint,
      tolerance = tolerance_abs,
      relative_gap = abs(built$t - achieved_constraint) / gr$total,
      relaxed = abs(built$t - achieved_constraint) > 1e-9 & tolerance_abs > 0,
      within_tolerance = abs(built$t - achieved_constraint) <= tolerance_abs +
        1e-8 * max(gr$total, 1),
      stringsAsFactors = FALSE
    )
  }

  structure(list(
    data = do.call(rbind, res_rows),
    log = do.call(rbind, logs),
    achieved = achieved,
    relaxation = do.call(rbind, relaxation),
    provenance = list(
      method = "soft",
      distance = "soft_linear",
      tolerance = tolerance_by_dim,
      init_weight = init_weight,
      na = na,
      dims = dvars,
      by = target$by,
      max_outer = as.integer(max_outer),
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_lincal_package_version()
    )
  ), class = "wf_weights")
}
