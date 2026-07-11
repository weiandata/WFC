# ============================================================================
# WFC Extension 3 -- reference implementation, part 3 of 3 (releases 0.14-0.15)
# Method-family extensions and deeper diagnostics. Base R only.
#
# Prototype code: source AFTER library(WFC).
#
# Contents:
#   1. wf_calibrate_soft() -- penalized (ridge) calibration      [design §7.1]
#   2. wf_calibrate_ebal() -- entropy balancing                  [design §7.2]
#   3. wf_attrition()      -- panel retention weighting          [design §8]
#   4. wf_influence()      -- per-unit leverage diagnostics      [design §8]
#
# k-source wf_blend() is a straightforward generalization of R/blend.R
# (lambda becomes a simplex row per cell) and is left to the implementation
# pass; it needs no new algorithm.
# ============================================================================

# ----------------------------------------------------------------------------
# 0. Shared constraint builder -------------------------------------------------
# Same construction as the packaged linear-calibration engine: one total
# column plus one dummy column per non-reference category of each dimension.
# ----------------------------------------------------------------------------

.wf_soft_build <- function(sub, dvars, gr) {
  n <- nrow(sub)
  cols <- list(rep(1, n))
  t <- gr$total
  labels <- "total"
  for (d in dvars) {
    lev <- names(gr$margins[[d]])
    for (l in lev[-1]) {
      cols[[length(cols) + 1]] <- as.numeric(trimws(as.character(sub[[d]])) == l)
      t <- c(t, gr$margins[[d]][[l]])
      labels <- c(labels, paste0(d, "=", l))
    }
  }
  list(X = do.call(cbind, cols), t = t, labels = labels)
}

# ----------------------------------------------------------------------------
# 1. Soft (penalized / ridge) calibration -------------------------------------
#
# Hard calibration forces X'w = t exactly; when a margin is unsupportable the
# only remedies are collapsing or stopping. Soft calibration minimizes
#
#   (1/2) (w - d)' D^{-1} (w - d)  +  (1/2) (t - X'w)' Phi^{-1} (t - X'w)
#
# with D = diag(d) and Phi = diag(phi_j) >= 0 the per-constraint slack. The
# closed form is
#
#   s = (Phi + X' D X)^{-1} (t - X'd);   w = d + D X s;   gap = Phi s.
#
# phi_j = 0 keeps constraint j exact (always: the group total). For the rest,
# a small outer loop shrinks phi_j until every |gap_j| lies within the user's
# declared tolerance -- so the relaxation is bounded and fully reported.
# ----------------------------------------------------------------------------

wf_calibrate_soft <- function(sample, target, tolerance = 0.02,
                              init_weight = NULL, id = NULL,
                              na = c("drop", "error"), max_outer = 25) {
  na <- match.arg(na)
  stopifnot(inherits(target, "wf_target"))
  dvars <- target$dims

  na_mask <- Reduce(`|`, lapply(dvars, function(d) is.na(sample[[d]])))
  if (any(na_mask)) {
    if (na == "error") stop(sprintf("%d row(s) have NA in calibration dimensions.", sum(na_mask)))
    warning(sprintf("na='drop': removed %d row(s) with NA in calibration dimensions.", sum(na_mask)))
    sample <- sample[!na_mask, , drop = FALSE]
  }

  gkey <- if (is.null(target$by)) rep("_all_", nrow(sample))
          else trimws(as.character(sample[[target$by]]))
  ids <- if (is.null(id)) as.character(seq_len(nrow(sample)))
         else trimws(as.character(sample[[id]]))
  iw <- if (is.null(init_weight)) NULL else as.numeric(sample[[init_weight]])

  res_rows <- list(); logs <- list(); relax <- list()
  for (g in intersect(names(target$groups), unique(gkey))) {
    sel <- which(gkey == g)
    gr <- target$groups[[g]]
    built <- .wf_soft_build(sample[sel, , drop = FALSE], dvars, gr)
    X <- built$X; t <- built$t
    d <- if (is.null(iw)) rep(gr$total / length(sel), length(sel)) else iw[sel]

    p <- ncol(X)
    tol_abs <- c(0, rep(tolerance * gr$total, p - 1))   # total is exact
    phi <- c(0, rep((tolerance * gr$total)^2, p - 1))   # any positive start
    XtDX <- crossprod(X, X * d)
    r0 <- t - as.numeric(crossprod(X, d))

    w <- d; gap <- r0
    for (it in seq_len(max_outer)) {
      M <- XtDX + diag(phi, p)
      s <- tryCatch(solve(M, r0), error = function(e) NULL)
      if (is.null(s)) stop(sprintf("Group '%s': singular soft-calibration system.", g))
      w <- d + d * as.numeric(X %*% s)
      gap <- phi * s
      over <- which(abs(gap) > tol_abs & tol_abs > 0)
      if (length(over) == 0) break
      phi[over] <- phi[over] * (tol_abs[over] / abs(gap[over])) * 0.5
    }
    if (any(w <= 0)) {
      warning(sprintf(
        "Group '%s': %d non-positive weight(s) from the linear soft distance; production code should switch to a bounded distance here.",
        g, sum(w <= 0)))
    }

    res_rows[[g]] <- data.frame(id = ids[sel], group = g, weight = w,
                                feature = 1 / w, stringsAsFactors = FALSE)
    relax[[g]] <- data.frame(
      group = g, constraint = built$labels, target = t,
      achieved = as.numeric(crossprod(X, w)),
      gap = gap, tolerance = tol_abs, relaxed = abs(gap) > 1e-9,
      stringsAsFactors = FALSE
    )
    logs[[g]] <- data.frame(group = g, n = length(sel),
                            iterations = it, converged = TRUE,
                            n_relaxed = sum(abs(gap) > 1e-9),
                            max_rel_gap = max(abs(gap)) / gr$total,
                            stringsAsFactors = FALSE)
  }

  structure(list(
    data = do.call(rbind, res_rows),
    log = do.call(rbind, logs),
    achieved = NULL,
    relaxation = do.call(rbind, relax),   # the soft-calibration audit table
    provenance = list(method = "soft", tolerance = tolerance,
                      dims = dvars, by = target$by, created = Sys.time())
  ), class = "wf_weights")
}

# ----------------------------------------------------------------------------
# 2. Entropy balancing (exponential-distance calibration) ---------------------
#
# Solves sum_i d_i exp(x_i'lambda) x_i = t by damped Newton: the calibrated
# weights w = d exp(X lambda) minimize KL(w || d) subject to the constraints.
# Accepts the standard wf_target margins plus optional continuous `moments`
# (named vector of target MEANS for numeric sample columns) -- the case plain
# raking cannot handle.
# ----------------------------------------------------------------------------

wf_calibrate_ebal <- function(sample, target, moments = NULL,
                              id = NULL, tol = 1e-8, max_iter = 100) {
  stopifnot(inherits(target, "wf_target"))
  dvars <- target$dims
  gkey <- if (is.null(target$by)) rep("_all_", nrow(sample))
          else trimws(as.character(sample[[target$by]]))
  ids <- if (is.null(id)) as.character(seq_len(nrow(sample)))
         else trimws(as.character(sample[[id]]))

  res_rows <- list(); logs <- list()
  for (g in intersect(names(target$groups), unique(gkey))) {
    sel <- which(gkey == g)
    gr <- target$groups[[g]]
    sub <- sample[sel, , drop = FALSE]
    built <- .wf_soft_build(sub, dvars, gr)
    X <- built$X; t <- built$t
    if (!is.null(moments)) {
      for (mv in names(moments)) {
        X <- cbind(X, as.numeric(sub[[mv]]))
        t <- c(t, moments[[mv]] * gr$total)   # target mean -> target total
      }
    }
    d <- rep(gr$total / length(sel), length(sel))

    lambda <- rep(0, ncol(X))
    w <- d
    maxr <- Inf; it <- 0L
    while (it < max_iter) {
      resid <- t - as.numeric(crossprod(X, w))
      maxr <- max(abs(resid)) / gr$total
      if (maxr < tol) break
      it <- it + 1L
      jac <- crossprod(X, X * w)
      step <- tryCatch(solve(jac, resid), error = function(e) NULL)
      if (is.null(step)) stop(sprintf("Group '%s': singular entropy-balancing system.", g))
      alpha <- 1
      repeat {
        w_try <- d * exp(as.numeric(X %*% (lambda + alpha * step)))
        r_try <- max(abs(t - as.numeric(crossprod(X, w_try)))) / gr$total
        if (all(is.finite(w_try)) && is.finite(r_try) && r_try < maxr) break
        alpha <- alpha / 2
        if (alpha < 1e-10) break
      }
      lambda <- lambda + alpha * step
      w <- d * exp(as.numeric(X %*% lambda))
    }
    if (maxr >= tol) {
      stop(sprintf("Group '%s': entropy balancing did not converge (residual %.3g). The moment targets may be outside the sample's convex hull.",
                   g, maxr))
    }
    res_rows[[g]] <- data.frame(id = ids[sel], group = g, weight = w,
                                feature = 1 / w, stringsAsFactors = FALSE)
    logs[[g]] <- data.frame(group = g, n = length(sel), iterations = it,
                            converged = TRUE, max_resid = maxr,
                            kl_divergence = sum(w * log(w / d)) / sum(w),
                            stringsAsFactors = FALSE)
  }

  structure(list(
    data = do.call(rbind, res_rows),
    log = do.call(rbind, logs),
    achieved = NULL,
    provenance = list(method = "ebal", moments = names(moments),
                      dims = dvars, by = target$by, created = Sys.time())
  ), class = "wf_weights")
}

# ----------------------------------------------------------------------------
# 3. wf_attrition() -- panel retention weighting -------------------------------
#
# Same discipline as wf_propensity(): model wave-to-wave retention with a
# base-R glm, invert the fitted retention probability into a stage-1 weight
# for the retained units (stabilized by default), and ship balance
# diagnostics comparing the reweighted retainees against the full prior wave.
# Chains across waves through wf_compose().
# ----------------------------------------------------------------------------

wf_attrition <- function(panel, retained, formula, id = NULL,
                         stabilize = TRUE, trim = NULL) {
  stopifnot(is.data.frame(panel), retained %in% names(panel))
  keep <- panel[[retained]]
  if (!is.logical(keep)) keep <- as.integer(keep) == 1L
  if (any(is.na(keep))) stop("`retained` must not contain NA.")
  predictors <- all.vars(formula[[3]])
  na_rows <- Reduce(`|`, lapply(predictors, function(p) is.na(panel[[p]])))
  if (any(na_rows)) stop(sprintf("%d row(s) have NA in retention-model predictors.", sum(na_rows)))

  df <- panel
  df$.wf_retained <- as.integer(keep)
  fit <- stats::glm(stats::reformulate(predictors, ".wf_retained"),
                    family = stats::binomial(), data = df)
  phat <- stats::fitted(fit)

  raw <- 1 / phat[keep]
  if (stabilize) raw <- mean(keep) * raw
  trimmed <- 0L
  if (!is.null(trim)) {
    cap <- trim * stats::median(raw)
    trimmed <- sum(raw > cap)
    raw[raw > cap] <- cap
  }
  w <- raw / mean(raw)

  ids <- if (is.null(id)) as.character(which(keep))
         else trimws(as.character(panel[[id]][keep]))

  # balance: reweighted retainees vs the full prior wave
  balance <- do.call(rbind, lapply(predictors, function(p) {
    x <- panel[[p]]
    if (!is.numeric(x)) x <- as.numeric(as.factor(x))
    sd_pool <- stats::sd(x)
    data.frame(
      variable = p,
      smd_unweighted = (mean(x[keep]) - mean(x)) / sd_pool,
      smd_weighted = (stats::weighted.mean(x[keep], w) - mean(x)) / sd_pool,
      stringsAsFactors = FALSE
    )
  }))

  structure(list(
    data = data.frame(id = ids, group = "_panel_", weight = w,
                      feature = 1 / w, stringsAsFactors = FALSE),
    log = data.frame(group = "_panel_", n = sum(keep),
                     n_lost = sum(!keep), retention = mean(keep),
                     trimmed = trimmed, stringsAsFactors = FALSE),
    achieved = NULL,
    balance = balance,
    provenance = list(method = "attrition", predictors = predictors,
                      stabilize = stabilize, trim = trim,
                      created = Sys.time())
  ), class = "wf_weights")
}

# ----------------------------------------------------------------------------
# 4. wf_influence() -- per-unit leverage diagnostics ---------------------------
#
# The practical question behind most trimming debates: WHICH respondents
# drive the extreme weights? Reports, per unit: the weight ratio to the group
# mean, the unit's share of the deff mass (w_i^2 / sum w^2), and -- for the
# `top` most extreme units -- the group design effect recomputed without the
# unit (leave-one-out).
# ----------------------------------------------------------------------------

wf_influence <- function(w, top = 20) {
  stopifnot(inherits(w, "wf_weights"))
  parts <- split(seq_len(nrow(w$data)), w$data$group)
  rows <- lapply(names(parts), function(g) {
    idx <- parts[[g]]
    wt <- w$data$weight[idx]
    data.frame(
      id = w$data$id[idx],
      group = g,
      weight = wt,
      ratio_to_mean = wt / mean(wt),
      deff_share = wt^2 / sum(wt^2),
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)
  tab <- tab[order(-tab$ratio_to_mean), ]
  rownames(tab) <- NULL

  n_top <- min(top, nrow(tab))
  tab$deff_loo <- NA_real_
  for (k in seq_len(n_top)) {
    g <- tab$group[k]
    wt <- w$data$weight[w$data$group == g]
    # leave-one-out: drop one instance of this unit's weight
    wt_loo <- wt[-match(tab$weight[k], wt)]
    tab$deff_loo[k] <- 1 + (stats::sd(wt_loo) / mean(wt_loo))^2
  }
  gdeff <- vapply(names(parts), function(g) {
    wt <- w$data$weight[w$data$group == g]
    1 + (stats::sd(wt) / mean(wt))^2
  }, numeric(1))
  tab$deff_group <- gdeff[tab$group]
  tab$deff_drop_if_removed <- tab$deff_group - tab$deff_loo

  structure(list(table = tab, top = n_top), class = "wf_influence")
}

print.wf_influence <- function(x, ...) {
  cat(sprintf("<wf_influence>  top %d most extreme unit(s):\n", x$top))
  cols <- c("id", "group", "weight", "ratio_to_mean", "deff_share",
            "deff_group", "deff_loo")
  print(utils::head(x$table[, cols], x$top), row.names = FALSE, digits = 3)
  invisible(x)
}
