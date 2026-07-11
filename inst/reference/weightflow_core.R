# ============================================================================
# weightflow 0.1 -- core reference implementation (R/core.R)
# Zero hard dependencies. All exported symbols are prefixed `wf_`.
# Workflow discipline: wf_precheck() -> wf_rake() -> wf_diagnose()
# ============================================================================

# ----------------------------------------------------------------------------
# 0. Condition system --------------------------------------------------------
# ----------------------------------------------------------------------------

wf_abort <- function(message, class, data = list()) {
  stop(structure(
    class = c(class, "wf_error", "error", "condition"),
    list(message = message, call = sys.call(-1), data = data)
  ))
}

wf_warn <- function(message, class, data = list()) {
  warning(structure(
    class = c(class, "wf_warning", "warning", "condition"),
    list(message = message, call = sys.call(-1), data = data)
  ))
}

.chr <- function(x) trimws(as.character(x))

.require_cols <- function(df, cols, what) {
  miss <- setdiff(cols, names(df))
  if (length(miss) > 0)
    wf_abort(sprintf("%s is missing column(s): %s", what,
                     paste(miss, collapse = ", ")),
             "wf_error_schema", list(missing = miss))
}

# ----------------------------------------------------------------------------
# 1. Dimension specification -------------------------------------------------
# ----------------------------------------------------------------------------

#' Declare calibration dimensions.
#' @param ... name = levels pairs; levels may be NULL (inferred from target).
#' @param .collapse named list of ladders; each ladder is a named list of maps
#'        (old category -> new category, as a named character vector).
wf_dims <- function(..., .collapse = list()) {
  vars <- list(...)
  if (length(vars) == 0 || is.null(names(vars)) || any(names(vars) == ""))
    wf_abort("wf_dims() requires named arguments: dimension = levels (or NULL).",
             "wf_error_input")
  vars <- lapply(vars, function(v) if (is.null(v)) NULL else .chr(v))
  bad <- setdiff(names(.collapse), names(vars))
  if (length(bad) > 0)
    wf_abort(sprintf("Collapse ladder(s) for unknown dimension(s): %s",
                     paste(bad, collapse = ", ")),
             "wf_error_input", list(unknown = bad))
  structure(list(vars = vars, collapse = .collapse), class = "wf_dims")
}

# ----------------------------------------------------------------------------
# 2. Canonical target object and constructors --------------------------------
# ----------------------------------------------------------------------------

.wf_new_target <- function(mode, by, dims, groups, meta = list()) {
  tgt <- structure(list(mode = mode, by = by, dims = dims,
                        groups = groups, meta = meta),
                   class = "wf_target")
  .wf_validate_target(tgt)
  tgt
}

.wf_validate_target <- function(tgt, tol = 1e-8) {
  for (g in names(tgt$groups)) {
    gr <- tgt$groups[[g]]
    if (!is.finite(gr$total) || gr$total <= 0)
      wf_abort(sprintf("Group '%s': target total must be positive and finite.", g),
               "wf_error_input", list(group = g, total = gr$total))
    for (d in tgt$dims) {
      m <- gr$margins[[d]]
      if (is.null(m) || is.null(names(m)))
        wf_abort(sprintf("Group '%s', dim '%s': margins missing or unnamed.", g, d),
                 "wf_error_internal", list(group = g, dim = d))
      if (any(!is.finite(m)) || any(m < 0))
        wf_abort(sprintf("Group '%s', dim '%s': margins must be finite and >= 0.",
                         g, d), "wf_error_input", list(group = g, dim = d))
      if (abs(sum(m) - gr$total) > tol * gr$total)
        wf_abort(sprintf(
          "Group '%s', dim '%s': margins sum to %.6g but total is %.6g. %s",
          g, d, sum(m), gr$total,
          "Additivity is required so IPF preserves the group total."),
          "wf_error_input", list(group = g, dim = d))
    }
  }
  invisible(TRUE)
}

.wf_group_keys <- function(df, by, by_key = NULL) {
  if (!is.null(by_key)) {
    if (is.function(by_key)) return(.chr(by_key(df)))
    .require_cols(df, by_key, "population data")
    return(.chr(df[[by_key]]))
  }
  if (is.null(by)) return(rep("_all_", nrow(df)))
  .require_cols(df, by, "data")
  .chr(df[[by]])
}

.wf_scale_groups <- function(groups, scale, sample_n = NULL, totals = NULL) {
  if (scale == "population") return(groups)
  for (g in names(groups)) {
    new_total <-
      if (scale == "sample") {
        if (is.null(sample_n) || is.na(sample_n[g]))
          wf_abort(sprintf(
            "scale='sample' needs the sample: no size found for group '%s'.", g),
            "wf_error_input", list(group = g))
        sample_n[g]
      } else {
        if (is.null(totals) || is.na(totals[g]))
          wf_abort(sprintf("scale='custom' requires totals['%s'].", g),
                   "wf_error_input", list(group = g))
        totals[g]
      }
    f <- new_total / groups[[g]]$total
    groups[[g]]$total   <- unname(new_total)
    groups[[g]]$margins <- lapply(groups[[g]]$margins, function(m) m * f)
  }
  groups
}

#' Target from external population data in an arbitrary format.
#' Only `key_map`-ed columns, `count`, and the group key are ever read.
wf_target_population <- function(pop, key_map, count, dims,
                                 by = NULL, by_key = NULL,
                                 scale = c("population", "sample", "custom"),
                                 sample = NULL, totals = NULL) {
  scale <- match.arg(scale)
  if (!is.data.frame(pop)) wf_abort("`pop` must be a data.frame.", "wf_error_input")
  dvars <- names(dims$vars)
  if (is.null(names(key_map)) || !setequal(names(key_map), dvars))
    wf_abort("`key_map` must be a named vector mapping every wf_dims dimension to a population column.",
             "wf_error_schema", list(expected = dvars, got = names(key_map)))
  .require_cols(pop, unname(key_map), "population data")
  .require_cols(pop, count, "population data")

  cnt <- pop[[count]]
  if (any(is.na(cnt)))
    wf_abort(sprintf("Population count column '%s' has %d NA value(s).",
                     count, sum(is.na(cnt))), "wf_error_input")
  if (any(cnt < 0))
    wf_abort(sprintf("Population count column '%s' has negative values.", count),
             "wf_error_input")

  gkey <- .wf_group_keys(pop, by, by_key)
  groups <- list()
  for (g in sort(unique(gkey))) {
    sel <- gkey == g
    margins <- list()
    for (d in dvars) {
      v <- .chr(pop[[key_map[[d]]]][sel])
      m <- tapply(cnt[sel], v, sum)
      margins[[d]] <- m[m > 0]           # zero-count categories drop out
    }
    groups[[g]] <- list(total = sum(cnt[sel]), margins = margins)
  }

  sample_n <- NULL
  if (scale == "sample") {
    if (is.null(sample)) wf_abort("scale='sample' requires `sample`.", "wf_error_input")
    sample_n <- table(.wf_group_keys(sample, by))
    sample_n <- stats::setNames(as.numeric(sample_n), names(sample_n))
  }
  groups <- .wf_scale_groups(groups, scale, sample_n, totals)

  .wf_new_target("population", by, dvars, groups,
                 meta = list(scale = scale, created = Sys.time()))
}

#' Target from a weighted reference sample (feature value = 1/design weight).
wf_target_reference <- function(ref, feature, dims, by = NULL,
                                feature_na  = c("error", "drop"),
                                feature_gt1 = c("warn", "allow")) {
  feature_na <- match.arg(feature_na); feature_gt1 <- match.arg(feature_gt1)
  dvars <- names(dims$vars)
  .require_cols(ref, c(dvars, feature, by), "reference sample")

  f <- ref[[feature]]
  bad_na <- which(is.na(f))
  if (length(bad_na) > 0) {
    msg <- sprintf("%d of %d reference rows (%.1f%%) have missing feature values.",
                   length(bad_na), nrow(ref), 100 * length(bad_na) / nrow(ref))
    if (feature_na == "error")
      wf_abort(paste(msg, "Use feature_na='drop' to exclude them from target construction."),
               "wf_error_input", list(rows = bad_na))
    wf_warn(paste(msg, "Dropped from target construction."),
            "wf_warning_data", list(rows = bad_na))
    ref <- ref[-bad_na, , drop = FALSE]; f <- ref[[feature]]
  }
  bad <- which(!is.finite(f) | f <= 0)
  if (length(bad) > 0)
    wf_abort(sprintf("Feature values must be finite and > 0; %d row(s) violate this (first: %s).",
                     length(bad), paste(utils::head(bad, 5), collapse = ", ")),
             "wf_error_input", list(rows = bad))
  if (any(f > 1) && feature_gt1 == "warn")
    wf_warn(sprintf("%d feature value(s) exceed 1; inclusion probabilities should lie in (0,1]. Is this column a weight rather than its reciprocal?",
                    sum(f > 1)), "wf_warning_data")

  w <- 1 / f
  gkey <- .wf_group_keys(ref, by)
  groups <- list()
  for (g in sort(unique(gkey))) {
    sel <- gkey == g
    margins <- lapply(dvars, function(d) {
      v <- .chr(ref[[d]][sel])
      if (any(is.na(ref[[d]][sel])))
        wf_abort(sprintf("Reference sample: NA in dimension '%s' (group '%s'). Clean or drop these rows before target construction.",
                         d, g), "wf_error_input", list(group = g, dim = d))
      m <- tapply(w[sel], v, sum); m[m > 0]
    })
    names(margins) <- dvars
    groups[[g]] <- list(total = sum(w[sel]), margins = margins)
  }
  .wf_new_target("reference", by, dvars, groups,
                 meta = list(created = Sys.time()))
}

# ----------------------------------------------------------------------------
# 3. Precheck ----------------------------------------------------------------
# ----------------------------------------------------------------------------

.wf_issue <- function(group, dim, category, check, severity, detail) {
  data.frame(group = group, dim = dim, category = category, check = check,
             severity = severity, detail = detail, stringsAsFactors = FALSE)
}

wf_precheck <- function(sample, target, id = NULL,
                        na = c("fractional", "drop", "error"),
                        max_na_dims = 2, thin_min = 5, risk_ratio = 10) {
  na <- match.arg(na)
  iss <- list()
  dvars <- target$dims

  miss <- setdiff(c(dvars, target$by), names(sample))
  if (length(miss) > 0) {
    iss[[length(iss) + 1]] <- .wf_issue("*", paste(miss, collapse = ","), NA,
      "schema_missing_var", "error",
      sprintf("Sample is missing variable(s): %s", paste(miss, collapse = ", ")))
    out <- do.call(rbind, iss)
    return(structure(list(issues = out, ok = FALSE, na = na),
                     class = "wf_precheck"))
  }

  if (!is.null(id)) {
    dup <- sum(duplicated(sample[[id]]))
    if (dup > 0)
      iss[[length(iss) + 1]] <- .wf_issue("*", NA, NA, "dup_id", "error",
        sprintf("%d duplicated value(s) in id column '%s'.", dup, id))
  }

  gkey <- .wf_group_keys(sample, target$by)
  if (!is.null(target$by) && any(is.na(sample[[target$by]])))
    iss[[length(iss) + 1]] <- .wf_issue("*", target$by, NA, "na_group", "error",
      sprintf("%d row(s) have NA in grouping variable '%s'.",
              sum(is.na(sample[[target$by]])), target$by))

  s_only <- setdiff(unique(gkey), names(target$groups))
  t_only <- setdiff(names(target$groups), unique(gkey))
  if (length(s_only) > 0)
    iss[[length(iss) + 1]] <- .wf_issue("*", target$by, NA, "group_unmatched",
      "error", sprintf("Group(s) in sample but not in target: %s",
                       paste(s_only, collapse = ", ")))
  if (length(t_only) > 0)
    iss[[length(iss) + 1]] <- .wf_issue("*", target$by, NA, "group_unmatched",
      "warning", sprintf("Group(s) in target but not in sample (ignored): %s",
                         paste(t_only, collapse = ", ")))

  na_mat <- sapply(dvars, function(d) is.na(sample[[d]]))
  if (is.null(dim(na_mat))) na_mat <- matrix(na_mat, nrow = nrow(sample))
  n_na_dims <- rowSums(na_mat)
  over <- which(n_na_dims > max_na_dims)
  if (length(over) > 0)
    iss[[length(iss) + 1]] <- .wf_issue("*", NA, NA, "na_overload", "error",
      sprintf("%d row(s) have NA in more than %d dimensions (first rows: %s).",
              length(over), max_na_dims,
              paste(utils::head(over, 5), collapse = ", ")))
  if (na == "error" && any(n_na_dims > 0))
    iss[[length(iss) + 1]] <- .wf_issue("*", NA, NA, "na_load", "error",
      sprintf("na='error': %d row(s) contain NA in calibration dimensions.",
              sum(n_na_dims > 0)))

  for (g in intersect(names(target$groups), unique(gkey))) {
    sel <- gkey == g
    n_g <- sum(sel)
    for (d in dvars) {
      v      <- .chr(sample[[d]][sel])
      is_na  <- is.na(sample[[d]][sel])
      n_na_d <- sum(is_na)
      tg     <- target$groups[[g]]$margins[[d]]
      share_t <- tg / sum(tg)
      cnt <- table(v[!is_na])

      unk <- setdiff(names(cnt), names(tg))
      if (length(unk) > 0)
        iss[[length(iss) + 1]] <- .wf_issue(g, d, paste(unk, collapse = ","),
          "cat_unknown_in_sample", "error",
          sprintf("Categories in sample with no target share: %s (%d row(s)). Collapse or recode.",
                  paste(unk, collapse = ", "), sum(cnt[unk])))

      for (k in names(tg)) {
        n_k <- if (k %in% names(cnt)) cnt[[k]] else 0L
        eff_support <- n_k + if (na == "fractional") n_na_d else 0L
        if (eff_support == 0)
          iss[[length(iss) + 1]] <- .wf_issue(g, d, k, "cat_infeasible", "error",
            sprintf("Target share %.1f%% but zero sample support. IPF cannot converge; collapse this category.",
                    100 * share_t[[k]]))
        else if (n_k < thin_min && share_t[[k]] > 0.01)
          iss[[length(iss) + 1]] <- .wf_issue(g, d, k, "support_thin", "warning",
            sprintf("Only %d respondent(s) for a %.1f%% target share.",
                    n_k, 100 * share_t[[k]]))
        if (n_k > 0) {
          ratio <- share_t[[k]] / (n_k / max(n_g - n_na_d, 1))
          if (ratio > risk_ratio)
            iss[[length(iss) + 1]] <- .wf_issue(g, d, k, "risk_extreme_ratio",
              "warning",
              sprintf("Target/sample share ratio %.1f: expect weights ~%.0fx the mean; consider collapsing.",
                      ratio, ratio))
        }
      }
      if (n_na_d > 0)
        iss[[length(iss) + 1]] <- .wf_issue(g, d, NA, "na_load", "note",
          sprintf("%d row(s) (%.1f%%) NA on this dimension; policy: %s.",
                  n_na_d, 100 * n_na_d / n_g, na))
    }
  }

  issues <- if (length(iss) > 0) do.call(rbind, iss) else
    .wf_issue(character(0), character(0), character(0),
              character(0), character(0), character(0))
  structure(list(issues = issues,
                 ok = !any(issues$severity == "error"), na = na),
            class = "wf_precheck")
}

print.wf_precheck <- function(x, ...) {
  cat(sprintf("<wf_precheck>  verdict: %s\n",
              if (x$ok) "OK - no blocking issues" else "BLOCKED"))
  if (nrow(x$issues) == 0) { cat("  no issues found\n"); return(invisible(x)) }
  tab <- table(x$issues$severity)
  cat(sprintf("  %s\n", paste(sprintf("%s: %d", names(tab), tab), collapse = " | ")))
  ord <- order(match(x$issues$severity, c("error", "warning", "note")))
  show <- utils::head(x$issues[ord, ], 20)
  for (i in seq_len(nrow(show)))
    cat(sprintf("  [%s] %s / %s%s -- %s\n", show$severity[i], show$group[i],
                show$dim[i],
                ifelse(is.na(show$category[i]), "",
                       paste0(":", show$category[i])),
                show$detail[i]))
  if (nrow(x$issues) > 20)
    cat(sprintf("  ... and %d more (see $issues)\n", nrow(x$issues) - 20))
  invisible(x)
}

# ----------------------------------------------------------------------------
# 4. Collapse plans -----------------------------------------------------------
# ----------------------------------------------------------------------------

#' Apply a category-merge map consistently to sample and target.
#' @param plan list(dim = <name>, map = c(old = new, ...))
wf_apply_collapse <- function(sample, target, plan) {
  d <- plan$dim; map <- plan$map
  if (!d %in% target$dims)
    wf_abort(sprintf("Collapse plan targets unknown dimension '%s'.", d),
             "wf_error_input")
  v <- .chr(sample[[d]]); hit <- !is.na(v) & v %in% names(map)
  v[hit] <- map[v[hit]]
  sample[[d]] <- v
  for (g in names(target$groups)) {
    m <- target$groups[[g]]$margins[[d]]
    key <- names(m); hit <- key %in% names(map); key[hit] <- map[key[hit]]
    target$groups[[g]]$margins[[d]] <- tapply(as.numeric(m), key, sum)
  }
  .wf_validate_target(target)
  target$meta$collapsed <- c(target$meta$collapsed, list(plan))
  list(sample = sample, target = target)
}

# ----------------------------------------------------------------------------
# 5. Execution: wf_rake() -----------------------------------------------------
# ----------------------------------------------------------------------------

.grp_sum <- function(w, idx, K) {
  out <- numeric(K)
  rs <- rowsum(w, idx)
  out[as.integer(rownames(rs))] <- rs[, 1]
  out
}

.wf_ipf <- function(w, idx, tg_list, tol, max_iter, group) {
  it <- 0L; dev <- Inf
  while (it < max_iter && dev >= tol) {
    it <- it + 1L; dev <- 0
    for (d in seq_along(tg_list)) {
      tg <- tg_list[[d]]; K <- length(tg)
      cur <- .grp_sum(w, idx[[d]], K)
      if (any(tg > 0 & cur <= 0))
        wf_abort(sprintf(
          "Group '%s': category with positive target but zero current weight in dimension %d. Precheck should have caught this; possibly caused by trimming a lone supporter to zero.",
          group, d), "wf_error_feasibility", list(group = group, dim = d))
      ratio <- ifelse(cur > 0, tg / cur, 1)
      w <- w * ratio[idx[[d]]]
      dev <- max(dev, max(abs(ratio[cur > 0] - 1)))
    }
  }
  list(w = w, iterations = it, converged = dev < tol, final_dev = dev)
}

.wf_expand_group <- function(rows_chr, na_mask, margins, total) {
  n <- nrow(rows_chr); D <- ncol(rows_chr)
  base_w <- total / n
  pid <- integer(0); vals <- vector("list", D); w0 <- numeric(0)
  for (d in seq_len(D)) vals[[d]] <- character(0)

  complete <- which(rowSums(na_mask) == 0)
  if (length(complete) > 0) {
    pid <- complete
    for (d in seq_len(D)) vals[[d]] <- rows_chr[complete, d]
    w0 <- rep(base_w, length(complete))
  }

  incomplete <- which(rowSums(na_mask) > 0)
  if (length(incomplete) > 0) {
    pat <- apply(na_mask[incomplete, , drop = FALSE], 1,
                 function(z) paste(which(z), collapse = "-"))
    for (p in unique(pat)) {
      md   <- as.integer(strsplit(p, "-")[[1]])
      rows <- incomplete[pat == p]
      lev  <- lapply(md, function(d) names(margins[[d]]))
      grid <- expand.grid(lev, stringsAsFactors = FALSE)
      K    <- nrow(grid)
      share <- rep(1, K)
      for (j in seq_along(md))
        share <- share * (margins[[md[j]]][grid[[j]]] / sum(margins[[md[j]]]))
      pid <- c(pid, rep(rows, each = K))
      for (d in seq_len(D)) {
        vals[[d]] <- c(vals[[d]],
          if (d %in% md) rep(grid[[match(d, md)]], times = length(rows))
          else           rep(rows_chr[rows, d], each = K))
      }
      w0 <- c(w0, rep(base_w * share, times = length(rows)))
    }
  }
  list(pid = pid, vals = vals, w0 = w0, n_persons = n)
}

#' Calibrate sample weights to a wf_target by grouped raking.
wf_rake <- function(sample, target, id = NULL,
                    na = c("fractional", "drop", "error"),
                    trim = NULL, trim_cycles = 4,
                    tol = 1e-6, max_iter = 200, precheck = TRUE) {
  na <- match.arg(na)
  t0 <- Sys.time()

  if (precheck) {
    pc <- wf_precheck(sample, target, id = id, na = na)
    if (!pc$ok)
      wf_abort(sprintf(
        "Precheck reports %d blocking issue(s). Inspect wf_precheck(sample, target) and remediate (e.g. wf_apply_collapse) before raking.",
        sum(pc$issues$severity == "error")),
        "wf_error_feasibility", list(precheck = pc))
  }

  dvars <- target$dims
  if (na == "drop") {
    keep <- rowSums(sapply(dvars, function(d) is.na(sample[[d]]))) == 0
    if (any(!keep))
      wf_warn(sprintf("na='drop': removed %d row(s) with NA in calibration dimensions.",
                      sum(!keep)), "wf_warning_data")
    sample <- sample[keep, , drop = FALSE]
  }

  gkey <- .wf_group_keys(sample, target$by)
  ids  <- if (is.null(id)) seq_len(nrow(sample)) else sample[[id]]

  res_rows <- list(); logs <- list(); achieved <- list()
  for (g in intersect(names(target$groups), unique(gkey))) {
    sel  <- which(gkey == g)
    gr   <- target$groups[[g]]
    rows <- sapply(dvars, function(d) .chr(sample[[d]][sel]))
    if (is.null(dim(rows))) rows <- matrix(rows, nrow = length(sel))
    na_mask <- is.na(rows)

    ex  <- .wf_expand_group(rows, na_mask, gr$margins, gr$total)
    idx <- lapply(seq_along(dvars), function(d)
      match(ex$vals[[d]], names(gr$margins[[d]])))
    tgl <- lapply(dvars, function(d) as.numeric(gr$margins[[d]]))

    fit <- .wf_ipf(ex$w0, idx, tgl, tol, max_iter, g)
    w   <- fit$w
    trim_hits <- 0L

    if (!is.null(trim)) {
      mw <- gr$total / ex$n_persons
      lo <- trim[[1]] * mw; hi <- trim[[2]] * mw
      for (cy in seq_len(trim_cycles)) {
        pw  <- .grp_sum(w, ex$pid, ex$n_persons)
        fac <- pmin(pmax(pw, lo), hi) / pw
        if (all(abs(fac - 1) < 1e-12)) break
        w   <- w * fac[ex$pid]
        fit <- .wf_ipf(w, idx, tgl, tol, max_iter, g)
        w   <- fit$w
      }
      # final cap-and-redistribute: caps are respected AND the total is exact,
      # because the shortfall is reallocated only to un-capped persons
      pw <- .grp_sum(w, ex$pid, ex$n_persons)
      for (r in 1:50) {
        pw2  <- pmin(pmax(pw, lo), hi)
        free <- pw2 > lo & pw2 < hi
        gap  <- gr$total - sum(pw2)
        if (abs(gap) < 1e-9 * gr$total) { pw <- pw2; break }
        if (!any(free))
          wf_abort(sprintf(
            "Group '%s': trim bounds [%g, %g] x mean are infeasible (all persons at a bound). Widen `trim`.",
            g, trim[[1]], trim[[2]]),
            "wf_error_feasibility", list(group = g))
        pw2[free] <- pw2[free] * (sum(pw2[free]) + gap) / sum(pw2[free])
        pw <- pw2
      }
      trim_hits <- sum(pw <= lo + 1e-12 | pw >= hi - 1e-12)
      w <- w * (pw / .grp_sum(w, ex$pid, ex$n_persons))[ex$pid]
    }

    pw <- .grp_sum(w, ex$pid, ex$n_persons)
    achieved[[g]] <- lapply(seq_along(dvars), function(d)
      stats::setNames(.grp_sum(w, idx[[d]], length(tgl[[d]])),
                      names(gr$margins[[d]])))
    names(achieved[[g]]) <- dvars

    res_rows[[g]] <- data.frame(
      id = ids[sel], group = g, weight = pw, feature = 1 / pw,
      stringsAsFactors = FALSE)
    logs[[g]] <- data.frame(
      group = g, n = ex$n_persons, pseudo_rows = length(w),
      iterations = fit$iterations, converged = fit$converged,
      final_dev = fit$final_dev, trimmed = trim_hits,
      stringsAsFactors = FALSE)
  }

  structure(list(
    data = do.call(rbind, res_rows),
    log  = do.call(rbind, logs),
    achieved = achieved,
    provenance = list(
      dims = dvars, by = target$by, mode = target$mode, na = na,
      trim = trim, tol = tol, max_iter = max_iter,
      collapsed = target$meta$collapsed,
      created = t0, elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = "0.1.0")
  ), class = "wf_weights")
}

print.wf_weights <- function(x, ...) {
  cat(sprintf("<wf_weights>  %d unit(s) in %d group(s); mode: %s; converged: %d/%d\n",
              nrow(x$data), nrow(x$log), x$provenance$mode,
              sum(x$log$converged), nrow(x$log)))
  cat(sprintf("  weight range [%.4g, %.4g]; elapsed %.2fs\n",
              min(x$data$weight), max(x$data$weight), x$provenance$elapsed))
  invisible(x)
}

# ----------------------------------------------------------------------------
# 6. Diagnostics ---------------------------------------------------------------
# ----------------------------------------------------------------------------

wf_diagnose <- function(w, target = NULL, sample = NULL,
                        deff_ok = 3, deff_caveat = 10) {
  out <- lapply(split(w$data, w$data$group), function(d) {
    wt <- d$weight; cv <- stats::sd(wt) / mean(wt)
    data.frame(group = d$group[1], n = nrow(d),
               ess = round(sum(wt)^2 / sum(wt^2), 1),
               deff = round(1 + cv^2, 2),
               mean_w = mean(wt), min_w = min(wt), max_w = max(wt),
               max_over_mean = round(max(wt) / mean(wt), 1),
               stringsAsFactors = FALSE)
  })
  tab <- do.call(rbind, out)
  tab <- merge(tab, w$log[, c("group", "iterations", "converged", "trimmed")],
               by = "group")

  if (!is.null(target)) {
    # compare the margins the engine actually achieved (stored at fit time,
    # pseudo-row exact, so NA fractional allocation is handled correctly)
    merr <- vapply(tab$group, function(g) {
      e <- 0
      for (d in target$dims) {
        tg  <- target$groups[[g]]$margins[[d]]
        cur <- w$achieved[[g]][[d]][names(tg)]
        e <- max(e, max(abs(cur - tg) / tg))
      }
      e
    }, numeric(1))
    tab$margin_maxerr <- round(merr, 4)
  }

  tab$verdict <- ifelse(!tab$converged, "FAILED",
                 ifelse(tab$deff <= deff_ok, "OK",
                 ifelse(tab$deff <= deff_caveat, "usable with caveats",
                        "do not publish separately")))
  structure(list(table = tab), class = "wf_diagnostics")
}

print.wf_diagnostics <- function(x, ...) {
  cat("<wf_diagnostics>\n")
  print(x$table, row.names = FALSE)
  invisible(x)
}
