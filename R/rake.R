#' Run iterative proportional fitting for one group.
#'
#' @param w Initial weights.
#' @param idx Per-dimension integer category indices.
#' @param tg_list Per-dimension target margins.
#' @param tol Convergence tolerance.
#' @param max_iter Maximum iterations.
#' @param group Group key.
#' @keywords internal
#' @noRd
.wf_ipf <- function(w, idx, tg_list, tol, max_iter, group) {
  it <- 0L
  dev <- Inf
  while (it < max_iter && dev >= tol) {
    it <- it + 1L
    dev <- 0
    for (d in seq_along(tg_list)) {
      tg <- tg_list[[d]]
      K <- length(tg)
      cur <- .grp_sum(w, idx[[d]], K)
      if (any(tg > 0 & cur <= 0)) {
        wf_abort(sprintf(
          "Group '%s': category with positive target but zero current weight in dimension %d. Precheck should have caught this; possibly caused by trimming a lone supporter to zero.",
          group,
          d
        ), "wf_error_feasibility", list(group = group, dim = d))
      }
      ratio <- ifelse(cur > 0, tg / cur, 1)
      w <- w * ratio[idx[[d]]]
      dev <- max(dev, max(abs(ratio[cur > 0] - 1)))
    }
  }
  list(w = w, iterations = it, converged = dev < tol, final_dev = dev)
}

#' Expand one group for fractional NA allocation.
#'
#' @param rows_chr Character matrix of sample calibration keys.
#' @param na_mask Missingness matrix.
#' @param margins Target margins.
#' @param total Group total.
#' @keywords internal
#' @noRd
.wf_expand_group <- function(rows_chr, na_mask, margins, total, init = NULL) {
  n <- nrow(rows_chr)
  D <- ncol(rows_chr)
  base_w <- total / n
  rel <- if (is.null(init) || mean(init) == 0) rep(1, n) else init / mean(init)
  pid <- integer(0)
  vals <- vector("list", D)
  w0 <- numeric(0)
  for (d in seq_len(D)) {
    vals[[d]] <- character(0)
  }

  complete <- which(rowSums(na_mask) == 0)
  if (length(complete) > 0) {
    pid <- complete
    for (d in seq_len(D)) {
      vals[[d]] <- rows_chr[complete, d]
    }
    w0 <- base_w * rel[complete]
  }

  incomplete <- which(rowSums(na_mask) > 0)
  if (length(incomplete) > 0) {
    pat <- apply(na_mask[incomplete, , drop = FALSE], 1, function(z) paste(which(z), collapse = "-"))
    for (p in unique(pat)) {
      md <- as.integer(strsplit(p, "-")[[1]])
      rows <- incomplete[pat == p]
      lev <- lapply(md, function(d) names(margins[[d]]))
      grid <- expand.grid(lev, stringsAsFactors = FALSE)
      K <- nrow(grid)
      share <- rep(1, K)
      for (j in seq_along(md)) {
        share <- share * (margins[[md[j]]][grid[[j]]] / sum(margins[[md[j]]]))
      }
      pid <- c(pid, rep(rows, each = K))
      for (d in seq_len(D)) {
        vals[[d]] <- c(
          vals[[d]],
          if (d %in% md) {
            rep(grid[[match(d, md)]], times = length(rows))
          } else {
            rep(rows_chr[rows, d], each = K)
          }
        )
      }
      w0 <- c(
        w0,
        base_w * rel[rep(rows, each = K)] * rep(share, times = length(rows))
      )
    }
  }
  list(pid = pid, vals = vals, w0 = w0, n_persons = n)
}

#' Calibrate sample weights to a target by grouped raking
#'
#' Runs the precheck -> execute portion of the weighting workflow.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param id Optional unique unit identifier column.
#' @param na Missing calibration data policy.
#' @param trim Optional two-element lower/upper multiplier vector.
#' @param trim_cycles Number of trim/rerake cycles.
#' @param tol Convergence tolerance.
#' @param max_iter Maximum iterations.
#' @param precheck Whether to run `wf_precheck()` before raking.
#' @param init_weight Optional column of initial weights. If `NULL`, raking
#'   starts from uniform weights (unchanged behaviour).
#' @param parallel Whether to process independent target groups with forked
#'   parallelism where available. Windows falls back to serial execution.
#' @param progress Whether to show a `cli` progress bar when `cli` is installed.
#'
#' @return A `wf_weights` object.
#' @export
wf_rake <- function(sample, target, id = NULL,
                    na = c("fractional", "drop", "error"),
                    trim = NULL, trim_cycles = 4,
                    tol = 1e-6, max_iter = 200, precheck = TRUE,
                    init_weight = NULL,
                    parallel = FALSE, progress = FALSE) {
  na <- match.arg(na)
  t0 <- Sys.time()

  if (precheck) {
    pc <- wf_precheck(sample, target, id = id, na = na)
    if (!pc$ok) {
      wf_abort(sprintf(
        "Precheck reports %d blocking issue(s). Inspect wf_precheck(sample, target) and remediate (e.g. wf_apply_collapse) before raking.",
        sum(pc$issues$severity == "error")
      ), "wf_error_feasibility", list(precheck = pc))
    }
  }

  dvars <- target$dims
  if (na == "drop") {
    keep <- rowSums(sapply(dvars, function(d) is.na(sample[[d]]))) == 0
    if (any(!keep)) {
      wf_warn(
        sprintf("na='drop': removed %d row(s) with NA in calibration dimensions.", sum(!keep)),
        "wf_warning_data"
      )
    }
    sample <- sample[keep, , drop = FALSE]
  }

  if (is.null(init_weight)) {
    iw <- rep(1, nrow(sample))
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

  gkey <- .wf_group_keys(sample, target$by)
  ids <- if (is.null(id)) seq_len(nrow(sample)) else sample[[id]]

  fit_group <- function(g) {
    sel <- which(gkey == g)
    gr <- target$groups[[g]]
    rows <- sapply(dvars, function(d) .chr(sample[[d]][sel]))
    if (is.null(dim(rows))) {
      rows <- matrix(rows, nrow = length(sel))
    }
    na_mask <- is.na(rows)

    ex <- .wf_expand_group(rows, na_mask, gr$margins, gr$total, init = iw[sel])
    idx <- lapply(seq_along(dvars), function(d) {
      match(ex$vals[[d]], names(gr$margins[[d]]))
    })
    tgl <- lapply(dvars, function(d) as.numeric(gr$margins[[d]]))

    fit <- .wf_ipf(ex$w0, idx, tgl, tol, max_iter, g)
    w <- fit$w
    trim_hits <- 0L

    if (!is.null(trim)) {
      mw <- gr$total / ex$n_persons
      lo <- trim[[1]] * mw
      hi <- trim[[2]] * mw
      for (cy in seq_len(trim_cycles)) {
        pw <- .grp_sum(w, ex$pid, ex$n_persons)
        fac <- pmin(pmax(pw, lo), hi) / pw
        if (all(abs(fac - 1) < 1e-12)) {
          break
        }
        w <- w * fac[ex$pid]
        fit <- .wf_ipf(w, idx, tgl, tol, max_iter, g)
        w <- fit$w
      }
      pw <- .grp_sum(w, ex$pid, ex$n_persons)
      for (r in 1:50) {
        pw2 <- pmin(pmax(pw, lo), hi)
        free <- pw2 > lo & pw2 < hi
        gap <- gr$total - sum(pw2)
        if (abs(gap) < 1e-9 * gr$total) {
          pw <- pw2
          break
        }
        if (!any(free)) {
          wf_abort(sprintf(
            "Group '%s': trim bounds [%g, %g] x mean are infeasible (all persons at a bound). Widen `trim`.",
            g,
            trim[[1]],
            trim[[2]]
          ), "wf_error_feasibility", list(group = g))
        }
        pw2[free] <- pw2[free] * (sum(pw2[free]) + gap) / sum(pw2[free])
        pw <- pw2
      }
      trim_hits <- sum(pw <= lo + 1e-12 | pw >= hi - 1e-12)
      w <- w * (pw / .grp_sum(w, ex$pid, ex$n_persons))[ex$pid]
    }

    if (!fit$converged) {
      worst <- which.max(vapply(seq_along(dvars), function(d) {
        cur <- .grp_sum(fit$w, idx[[d]], length(tgl[[d]]))
        max(abs(ifelse(cur > 0, tgl[[d]] / cur, 1) - 1))
      }, numeric(1)))
      wf_abort(sprintf(
        "Group '%s': IPF did not converge within %d iteration(s) (last deviation %.3g; worst dimension '%s'). Re-run wf_precheck() and collapse thin categories, or raise max_iter.",
        g,
        max_iter,
        fit$final_dev,
        dvars[[worst]]
      ), "wf_error_convergence", list(
        group = g,
        final_dev = fit$final_dev,
        worst_dim = dvars[[worst]],
        max_iter = max_iter
      ))
    }

    pw <- .grp_sum(w, ex$pid, ex$n_persons)
    achieved_g <- lapply(seq_along(dvars), function(d) {
      stats::setNames(.grp_sum(w, idx[[d]], length(tgl[[d]])), names(gr$margins[[d]]))
    })
    names(achieved_g) <- dvars

    res_row <- data.frame(
      id = ids[sel],
      group = g,
      weight = pw,
      feature = 1 / pw,
      stringsAsFactors = FALSE
    )
    log_row <- data.frame(
      group = g,
      n = ex$n_persons,
      pseudo_rows = length(w),
      iterations = fit$iterations,
      converged = fit$converged,
      final_dev = fit$final_dev,
      trimmed = trim_hits,
      stringsAsFactors = FALSE
    )
    list(data = res_row, log = log_row, achieved = achieved_g)
  }

  groups <- intersect(names(target$groups), unique(gkey))
  group_results <- .wf_parallel_map(
    as.list(groups),
    fit_group,
    use_parallel = parallel,
    progress = progress,
    label = "wf_rake"
  )
  names(group_results) <- groups
  res_rows <- lapply(group_results, `[[`, "data")
  logs <- lapply(group_results, `[[`, "log")
  achieved <- lapply(group_results, `[[`, "achieved")
  names(res_rows) <- groups
  names(logs) <- groups
  names(achieved) <- groups

  structure(list(
    data = do.call(rbind, res_rows),
    log = do.call(rbind, logs),
    achieved = achieved,
    provenance = list(
      dims = dvars,
      by = target$by,
      mode = target$mode,
      na = na,
      trim = trim,
      init_weight = init_weight,
      tol = tol,
      max_iter = max_iter,
      parallel = isTRUE(parallel),
      parallel_workers = attr(group_results, "workers"),
      progress = isTRUE(progress),
      collapsed = target$meta$collapsed,
      created = t0,
      elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_package_version()
    )
  ), class = "wf_weights")
}

#' Print calibrated weights
#'
#' @param x A `wf_weights` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_weights <- function(x, ...) {
  if (!is.null(x$provenance$method) && x$provenance$method == "soft") {
    relaxed <- if (is.data.frame(x$relaxation)) {
      sum(x$relaxation$relaxed)
    } else {
      NA_integer_
    }
    cat(sprintf(
      "<wf_weights>  %d unit(s) in %d group(s); method: soft calibration\n",
      nrow(x$data),
      nrow(x$log)
    ))
    cat(sprintf(
      "  weight range [%.4g, %.4g]; relaxed constraints: %s; elapsed %.2fs\n",
      min(x$data$weight),
      max(x$data$weight),
      as.character(relaxed),
      x$provenance$elapsed
    ))
    return(invisible(x))
  }
  if (!is.null(x$provenance$method) && x$provenance$method == "ebal") {
    cat(sprintf(
      "<wf_weights>  %d unit(s) in %d group(s); method: entropy balancing\n",
      nrow(x$data),
      nrow(x$log)
    ))
    cat(sprintf(
      "  weight range [%.4g, %.4g]; max residual %.2e; elapsed %.2fs\n",
      min(x$data$weight),
      max(x$data$weight),
      max(x$log$max_resid),
      x$provenance$elapsed
    ))
    return(invisible(x))
  }
  if (!is.null(x$provenance$method) &&
      x$provenance$method %in% c("greg", "logit")) {
    bnd <- if (is.null(x$provenance$bounds)) "none" else
      sprintf("[%.3g, %.3g]", x$provenance$bounds[1], x$provenance$bounds[2])
    cat(sprintf(
      "<wf_weights>  %d unit(s) in %d group(s); method: %s (%s); bounds: %s\n",
      nrow(x$data), nrow(x$log), x$provenance$method,
      x$provenance$distance, bnd
    ))
    cat(sprintf(
      "  weight range [%.4g, %.4g]; converged: %d/%d; elapsed %.2fs\n",
      min(x$data$weight), max(x$data$weight),
      sum(x$log$converged), nrow(x$log), x$provenance$elapsed
    ))
    return(invisible(x))
  }
  if (!is.null(x$provenance$method) && x$provenance$method == "propensity") {
    cat(sprintf(
      "<wf_weights>  %d unit(s) in %d group(s); method: propensity (%s / %s)\n",
      nrow(x$data),
      nrow(x$log),
      x$provenance$fit_method,
      x$provenance$weight
    ))
    cat(sprintf(
      "  weight range [%.4g, %.4g]; stabilized: %s; trimmed: %d; elapsed %.2fs\n",
      min(x$data$weight),
      max(x$data$weight),
      x$provenance$stabilize,
      x$provenance$trimmed,
      x$provenance$elapsed
    ))
    cat(sprintf(
      "  overlap: %d/%d online unit(s) above p > %.2f boundary\n",
      x$overlap$n_boundary,
      x$overlap$n_online,
      x$overlap$threshold
    ))
    return(invisible(x))
  }
  if (!is.null(x$provenance$method) && x$provenance$method == "poststrat") {
    cat(sprintf(
      "<wf_weights>  %d unit(s) in %d group(s); method: poststrat\n",
      nrow(x$data),
      nrow(x$log)
    ))
    cat(sprintf(
      "  weight range [%.4g, %.4g]; elapsed %.2fs\n",
      min(x$data$weight),
      max(x$data$weight),
      x$provenance$elapsed
    ))
    cat(sprintf(
      "  cells: %d raw -> %d resolved (median); groups using province granularity: %d\n",
      stats::median(x$log$n_cells_raw),
      stats::median(x$log$n_cells_resolved),
      sum(x$log$granularity_used == "province")
    ))
    cat(sprintf("  max group-total deviation: %.2e\n", max(x$log$total_dev)))
    return(invisible(x))
  }

  cat(sprintf(
    "<wf_weights>  %d unit(s) in %d group(s); mode: %s; converged: %d/%d\n",
    nrow(x$data),
    nrow(x$log),
    x$provenance$mode,
    sum(x$log$converged),
    nrow(x$log)
  ))
  cat(sprintf(
    "  weight range [%.4g, %.4g]; elapsed %.2fs\n",
    min(x$data$weight),
    max(x$data$weight),
    x$provenance$elapsed
  ))
  invisible(x)
}
