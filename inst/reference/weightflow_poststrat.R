# ============================================================================
# weightflow 0.2 -- post-stratification extension (R/poststrat.R)
# Source AFTER weightflow_core.R. Zero hard dependencies.
# Adds: wf_collapse_ladder(), wf_plan_poststrat(), wf_poststrat()
# Discipline: wf_plan_poststrat() -> wf_poststrat() -> wf_diagnose()
# ============================================================================

# ----------------------------------------------------------------------------
# 0. Cell-key helpers --------------------------------------------------------
# ----------------------------------------------------------------------------

# Build a single string key per row from the character dimension columns.
.wf_cell_key <- function(mat, dvars) {
  do.call(paste, c(lapply(dvars, function(d) mat[, d]), sep = "\r"))
}
.wf_split_key <- function(keys, dvars) {
  parts <- do.call(rbind, strsplit(keys, "\r", fixed = TRUE))
  df <- as.data.frame(parts, stringsAsFactors = FALSE)
  names(df) <- dvars
  df
}

# ----------------------------------------------------------------------------
# 1. Collapse ladder ---------------------------------------------------------
# ----------------------------------------------------------------------------

#' Declare an ordered, cumulative, validated collapse ladder.
#' Level 0 is the raw cells (implicit). Each `levelK = list(dim = c(old=new,...))`
#' argument adds one more merge, applied on top of all previous levels.
wf_collapse_ladder <- function(dims, ...) {
  if (!inherits(dims, "wf_dims"))
    wf_abort("`dims` must be a wf_dims object.", "wf_error_input")
  steps <- list(...)
  if (length(steps) > 0 && (is.null(names(steps)) || any(names(steps) == "")))
    wf_abort("Ladder levels must be named (e.g. level1 = list(...)).",
             "wf_error_input")
  dvars <- names(dims$vars)

  # Track the evolving category universe per dimension to validate cumulatively.
  # When dims declares explicit levels we validate against them from level 1;
  # when levels are NULL (unknown), we cannot check level-1 source categories,
  # but we DO seed the universe from level-1 maps so that later levels are
  # validated against categories the ladder itself has produced.
  universe <- lapply(dvars, function(d) dims$vars[[d]])
  names(universe) <- dvars
  for (lv in seq_along(steps)) {
    step <- steps[[lv]]
    bad_d <- setdiff(names(step), dvars)
    if (length(bad_d) > 0)
      wf_abort(sprintf("Ladder level '%s' references unknown dimension(s): %s",
                       names(steps)[lv], paste(bad_d, collapse = ", ")),
               "wf_error_input", list(level = names(steps)[lv], dims = bad_d))
    for (d in names(step)) {
      map <- step[[d]]
      if (is.null(names(map)))
        wf_abort(sprintf("Ladder level '%s', dim '%s': map must be a named vector (old=new).",
                         names(steps)[lv], d), "wf_error_input")
      if (!is.null(universe[[d]])) {
        unknown <- setdiff(names(map), universe[[d]])
        if (length(unknown) > 0)
          wf_abort(sprintf(
            "Ladder level '%s', dim '%s': source categories not present at this level: %s",
            names(steps)[lv], d, paste(unknown, collapse = ", ")),
            "wf_error_input", list(level = names(steps)[lv], dim = d,
                                   unknown = unknown))
        kept <- setdiff(universe[[d]], names(map))
        universe[[d]] <- unique(c(kept, unname(map)))
      } else {
        # unknown starting universe: seed it so later levels are checkable
        universe[[d]] <- unique(unname(map))
      }
    }
  }
  structure(list(dims = dvars, steps = steps, n_levels = length(steps)),
            class = "wf_collapse_ladder")
}

# Apply the cumulative maps for ladder levels 1..lv to a character matrix,
# returning the coarsened matrix. lv = 0 returns the input unchanged.
.wf_apply_ladder <- function(mat, ladder, lv) {
  if (lv == 0) return(mat)
  for (k in seq_len(lv)) {
    step <- ladder$steps[[k]]
    for (d in names(step)) {
      map <- step[[d]]; col <- mat[, d]
      hit <- !is.na(col) & col %in% names(map)
      col[hit] <- map[col[hit]]
      mat[, d] <- col
    }
  }
  mat
}

# ----------------------------------------------------------------------------
# 2. Resolution engine (shared by planner and executor) ----------------------
# ----------------------------------------------------------------------------

# For one group: decide, per raw cell, the lowest ladder level meeting min_cell.
# Returns per-raw-cell resolution + chosen granularity + orphan info.
.wf_resolve_group <- function(smat, jdf, dvars, ladder, min_cell,
                              granularity, group) {
  # raw (level-0) cell keys for sample and for population cells
  jmat <- as.matrix(jdf[, dvars, drop = FALSE])
  raw_pop_key <- .wf_cell_key(jmat, dvars)

  # precompute sample counts at each ladder level, keyed by coarsened cell
  max_lv <- ladder$n_levels
  # coarsened sample keys per level
  s_keys <- lapply(0:max_lv, function(lv)
    .wf_cell_key(.wf_apply_ladder(smat, ladder, lv), dvars))
  s_counts <- lapply(s_keys, function(k) table(k))
  # coarsened population-cell keys per level (maps each raw pop cell -> level key)
  p_keys <- lapply(0:max_lv, function(lv)
    .wf_cell_key(.wf_apply_ladder(jmat, ladder, lv), dvars))

  n_raw <- nrow(jdf)
  level_used <- integer(n_raw)
  resolved   <- character(n_raw)
  gran_used  <- granularity

  support_at <- function(lv, cellkeys) {
    tb <- s_counts[[lv + 1]]
    as.integer(ifelse(cellkeys %in% names(tb), tb[cellkeys], 0L))
  }

  # The resolved partition must be VALID: if two raw cells share an ancestor at
  # level k, they must resolve at the SAME level (otherwise population and sample
  # are aggregated on incompatible boundaries, leaking population). We therefore
  # decide the level of each MERGE GROUP, not each raw cell. Start everyone at
  # level 0; a coarsened cell at its current level is acceptable iff its combined
  # sample support >= min_cell. Under-supported cells push ALL their members up
  # one level; because pushing up can merge previously-separate cells, iterate to
  # a fixed point. Members of any coarsened key always move together, so the
  # result is a genuine partition.
  if (granularity == "adaptive") {
    # Correct adaptive partition via monotone level-raising to a fixed point.
    # Invariant we enforce: for the FINAL levels, every coarsened key contains
    # members all at the same level, and every kept cell has >= min_cell support.
    #
    # Rule 1 (support): a coarsened cell with < min_cell support raises all its
    #   members one level.
    # Rule 2 (partition validity): if raw cells A and B collapse to the same key
    #   at level L, and A has been raised to level L (or higher), then B — which
    #   would merge with A at L — must also be at level >= L. We enforce this by
    #   lifting, at each level L from coarse to fine, any cell whose level-L key
    #   is shared by a cell already at level >= L.
    settle <- rep(0L, n_raw)
    repeat {
      before <- settle
      # Rule 1
      keys <- vapply(seq_len(n_raw),
                     function(i) p_keys[[settle[i] + 1]][i], character(1))
      supp <- vapply(seq_len(n_raw),
                     function(i) support_at(settle[i], keys[i]), integer(1))
      under <- supp < min_cell & settle < max_lv
      if (any(under)) {
        bad <- unique(keys[under])
        settle[keys %in% bad & settle < max_lv] <-
          settle[keys %in% bad & settle < max_lv] + 1L
      }
      # Rule 2: propagate merges upward. For each level L, cells sharing an
      # L-key with a member already at level >= L must be lifted to L.
      for (L in 1:max_lv) {
        kL   <- p_keys[[L + 1]]
        hasL <- tapply(settle >= L, kL, any)      # some merger already at >= L?
        lift <- as.logical(hasL[kL]) & settle < L
        if (any(lift)) settle[lift] <- L
      }
      if (identical(settle, before)) break
    }
    final_keys <- vapply(seq_len(n_raw),
                         function(i) p_keys[[settle[i] + 1]][i], character(1))
    final_supp <- vapply(seq_len(n_raw),
                         function(i) support_at(settle[i], final_keys[i]),
                         integer(1))
    if (any(final_supp < min_cell)) {
      gran_used <- "province"
    } else {
      level_used <- settle
      resolved   <- final_keys
    }
  }

  if (gran_used == "province") {
    chosen <- NA_integer_
    for (lv in 0:max_lv) {
      supp <- support_at(lv, p_keys[[lv + 1]])
      if (all(supp >= min_cell)) { chosen <- lv; break }
    }
    if (is.na(chosen)) chosen <- max_lv
    level_used <- rep(chosen, n_raw)
    resolved   <- p_keys[[chosen + 1]]
  }

  supp_final <- vapply(seq_len(n_raw),
                       function(i) support_at(level_used[i], resolved[i]),
                       integer(1))
  orphan <- supp_final == 0

  list(raw_key = raw_pop_key, level_used = level_used, resolved = resolved,
       supp_final = supp_final, orphan = orphan, granularity_used = gran_used,
       s_keys = s_keys, p_keys = p_keys, jmat = jmat)
}

# For orphan cells, find nearest supported ancestor (one or more levels up)
# and reassign their resolved key to that ancestor. Returns updated resolved +
# a redistribution log.
.wf_redistribute <- function(res, min_cell, group) {
  n_raw <- length(res$resolved)
  redist <- list()
  max_lv <- length(res$s_keys) - 1
  # support of raw cell k at its currently-assigned level
  support_at_final <- function(res, k) {
    tb <- table(res$s_keys[[res$level_used[k] + 1]])
    key <- res$resolved[k]
    if (key %in% names(tb)) as.integer(tb[key]) else 0L
  }
  for (i in which(res$orphan)) {
    moved <- FALSE
    lv0 <- res$level_used[i]
    if (lv0 < max_lv) {
      for (lv in (lv0 + 1):max_lv) {
        anc <- res$p_keys[[lv + 1]][i]
        tb  <- table(res$s_keys[[lv + 1]])
        if (anc %in% names(tb) && tb[anc] > 0) {
          redist[[length(redist) + 1]] <- data.frame(
            group = group, orphan_cell = res$resolved[i],
            receiving_cell = anc, ancestor_level = lv,
            stringsAsFactors = FALSE)
          res$resolved[i]   <- anc
          res$level_used[i] <- lv
          res$orphan[i]     <- FALSE
          moved <- TRUE; break
        }
      }
    }
    if (!moved) {
      # Ladder exhausted: no coarsened ancestor of this cell has support.
      # Province-level fallback (requirement 5, redistribute): fold the orphan
      # population into the province's most-supported resolved cell, so no
      # population is lost. This is the coarsest possible reallocation and is
      # always logged for audit. It implies the strongest exchangeability
      # assumption, flagged to the analyst.
      supported <- which(!res$orphan)
      if (length(supported) == 0)
        wf_abort(sprintf("Group '%s': no resolved cell has any sample support; cannot post-stratify this group at all.",
                         group), "wf_error_feasibility", list(group = group))
      counts <- vapply(supported,
        function(k) support_at_final(res, k), integer(1))
      recv <- res$resolved[supported[which.max(counts)]]
      redist[[length(redist) + 1]] <- data.frame(
        group = group, orphan_cell = res$resolved[i],
        receiving_cell = recv, ancestor_level = -1L,   # -1 = province fallback
        stringsAsFactors = FALSE)
      res$resolved[i] <- recv
      res$orphan[i]   <- FALSE
    }
  }
  res$redist_log <- if (length(redist)) do.call(rbind, redist) else NULL
  res
}

# ----------------------------------------------------------------------------
# 3. Planner (precheck side): wf_plan_poststrat() ----------------------------
# ----------------------------------------------------------------------------

wf_plan_poststrat <- function(sample, target, min_cell, ladder,
                              granularity = c("adaptive", "province"),
                              empty_cell = c("redistribute", "flag", "error"),
                              id = NULL) {
  granularity <- match.arg(granularity); empty_cell <- match.arg(empty_cell)
  .wf_check_poststrat_args(sample, target, min_cell, ladder)
  dvars <- target$dims
  gkey  <- .wf_group_keys(sample, target$by)

  plan_rows <- list(); diag_rows <- list()
  for (g in intersect(names(target$joint), unique(gkey))) {
    sel  <- gkey == g
    smat <- as.matrix(sapply(dvars, function(d) .chr(sample[[d]][sel])))
    if (is.null(dim(smat))) smat <- matrix(smat, ncol = length(dvars),
                                           dimnames = list(NULL, dvars))
    jdf  <- target$joint[[g]]
    res  <- .wf_resolve_group(smat, jdf, dvars, ladder, min_cell, granularity, g)
    if (any(res$orphan) && empty_cell == "redistribute")
      res <- .wf_redistribute(res, min_cell, g)

    plan_rows[[g]] <- data.frame(
      group = g, jdf[, dvars, drop = FALSE], pop = jdf$pop,
      n_sample = res$supp_final, ladder_level = res$level_used,
      resolved_cell = res$resolved, orphan = res$orphan,
      stringsAsFactors = FALSE)
    diag_rows[[g]] <- data.frame(
      group = g, n_cells_raw = nrow(jdf),
      n_cells_resolved = length(unique(res$resolved)),
      granularity_used = res$granularity_used,
      n_at_level0 = sum(res$level_used == 0),
      max_level_used = max(res$level_used),
      n_orphan = sum(res$orphan),
      pop_orphan = sum(jdf$pop[res$orphan]),
      stringsAsFactors = FALSE)
  }
  structure(list(
    plan = do.call(rbind, plan_rows),
    diagnostics = do.call(rbind, diag_rows),
    settings = list(min_cell = min_cell, granularity = granularity,
                    empty_cell = empty_cell, ladder = ladder)),
    class = "wf_poststrat_plan")
}

print.wf_poststrat_plan <- function(x, ...) {
  d <- x$diagnostics
  cat(sprintf("<wf_poststrat_plan>  %d group(s); min_cell = %d\n",
              nrow(d), x$settings$min_cell))
  degr <- sum(d$granularity_used == "province")
  cat(sprintf("  granularity: %d adaptive, %d degraded to province-uniform\n",
              sum(d$granularity_used == "adaptive"), degr))
  cat(sprintf("  orphan cells (redistributed/flagged): %d across groups; pop moved: %s\n",
              sum(d$n_orphan), format(round(sum(d$pop_orphan)), big.mark = ",")))
  print(utils::head(d, 12), row.names = FALSE)
  if (nrow(d) > 12) cat(sprintf("  ... %d more groups (see $diagnostics)\n",
                                nrow(d) - 12))
  invisible(x)
}

# ----------------------------------------------------------------------------
# 4. Argument validation -----------------------------------------------------
# ----------------------------------------------------------------------------

.wf_check_poststrat_args <- function(sample, target, min_cell, ladder) {
  if (is.null(target$joint))
    wf_abort("Target has no joint cell table. Rebuild with wf_target_population(..., keep_joint = TRUE).",
             "wf_error_schema")
  if (!inherits(ladder, "wf_collapse_ladder"))
    wf_abort("`ladder` must be a wf_collapse_ladder object.", "wf_error_input")
  if (missing(min_cell) || length(min_cell) != 1 || !is.finite(min_cell) ||
      min_cell < 1 || min_cell != as.integer(min_cell))
    wf_abort("`min_cell` must be a single integer >= 1.", "wf_error_input")
  .require_cols(sample, c(target$dims, target$by), "sample")
  if (!identical(sort(ladder$dims), sort(target$dims)))
    wf_abort("Ladder dimensions do not match target dimensions.",
             "wf_error_schema",
             list(ladder = ladder$dims, target = target$dims))
  invisible(TRUE)
}

# ----------------------------------------------------------------------------
# 5. Executor: wf_poststrat() ------------------------------------------------
# ----------------------------------------------------------------------------

wf_poststrat <- function(sample, target, min_cell, ladder,
                         init_weight = NULL,
                         granularity = c("adaptive", "province"),
                         empty_cell = c("redistribute", "flag", "error"),
                         id = NULL, precheck = TRUE, tol = 1e-8) {
  granularity <- match.arg(granularity); empty_cell <- match.arg(empty_cell)
  t0 <- Sys.time()
  .wf_check_poststrat_args(sample, target, min_cell, ladder)

  dvars <- target$dims
  gkey  <- .wf_group_keys(sample, target$by)
  ids   <- if (is.null(id)) seq_len(nrow(sample)) else sample[[id]]
  iw    <- if (is.null(init_weight)) rep(1, nrow(sample)) else sample[[init_weight]]
  if (any(!is.finite(iw)) || any(iw <= 0))
    wf_abort("Initial weights must be finite and > 0.", "wf_error_input")

  res_rows <- list(); logs <- list(); reports <- list(); maps <- list()

  for (g in intersect(names(target$joint), unique(gkey))) {
    sel  <- which(gkey == g)
    smat <- as.matrix(sapply(dvars, function(d) .chr(sample[[d]][sel])))
    if (is.null(dim(smat))) smat <- matrix(smat, ncol = length(dvars),
                                           dimnames = list(NULL, dvars))
    jdf  <- target$joint[[g]]
    res  <- .wf_resolve_group(smat, jdf, dvars, ladder, min_cell, granularity, g)

    if (res$granularity_used == "province" && granularity == "adaptive")
      wf_warn(sprintf("Group '%s': adaptive resolution insufficient; degraded to province-uniform (level %d).",
                      g, max(res$level_used)), "wf_warning_quality",
              list(group = g))

    pop_flagged <- 0
    if (any(res$orphan)) {
      if (empty_cell == "error")
        wf_abort(sprintf("Group '%s': %d population cell(s) have zero sample support and empty_cell='error'.",
                         g, sum(res$orphan)), "wf_error_feasibility",
                 list(group = g, n_orphan = sum(res$orphan)))
      if (empty_cell == "redistribute") {
        res <- .wf_redistribute(res, min_cell, g)
        if (!is.null(res$redist_log))
          wf_warn(sprintf("Group '%s': redistributed %d orphan cell(s) into supported ancestors.",
                          g, nrow(res$redist_log)), "wf_warning_data",
                  list(group = g))
      } else { # flag: orphan population left unassigned
        pop_flagged <- sum(jdf$pop[res$orphan])
        wf_warn(sprintf("Group '%s': %d orphan cell(s) flagged; %s population left unassigned (province total will be short).",
                        g, sum(res$orphan),
                        format(round(pop_flagged), big.mark = ",")),
                "wf_warning_data", list(group = g))
      }
    }

    # ---- population per resolved cell (post-redistribution, orphans folded) --
    pop_by_res <- tapply(jdf$pop[!res$orphan], res$resolved[!res$orphan], sum)

    # ---- sample side: map each respondent to its resolved cell -----------------
    # A respondent's resolved cell is determined by applying, to the respondent,
    # the SAME level that its raw population cell was resolved at. We build, for
    # every level, the respondent's coarsened key, then pick the level assigned
    # to its raw population cell. Respondents whose raw cell is absent from the
    # population table (structural-zero population but nonzero sample) are folded
    # into the resolved cell of their nearest populated ancestor.
    lvl_of_raw <- stats::setNames(res$level_used, res$raw_key)
    s_raw      <- .wf_cell_key(smat, dvars)
    s_res      <- rep(NA_character_, length(sel))

    in_pop <- s_raw %in% res$raw_key
    if (any(in_pop)) {
      wr   <- which(in_pop)
      lv_i <- as.integer(lvl_of_raw[s_raw[in_pop]])
      s_res[in_pop] <- vapply(seq_along(wr), function(j)
        .wf_cell_key(.wf_apply_ladder(smat[wr[j], , drop = FALSE],
                                      ladder, lv_i[j]), dvars),
        character(1))
    }
    # respondents in cells absent from population: climb until their coarsened
    # key matches some resolved cell; if none, drop with warning.
    if (any(!in_pop)) {
      valid_res <- unique(res$resolved)
      for (idxrow in which(!in_pop)) {
        assigned <- NA_character_
        for (lv in 0:(length(res$s_keys) - 1)) {
          k <- .wf_cell_key(.wf_apply_ladder(smat[idxrow, , drop = FALSE],
                                             ladder, lv), dvars)
          if (k %in% valid_res) { assigned <- k; break }
        }
        s_res[idxrow] <- assigned
      }
      n_drop <- sum(is.na(s_res))
      if (n_drop > 0)
        wf_warn(sprintf("Group '%s': %d respondent(s) fall in cells with no populated resolved match; excluded.",
                        g, n_drop), "wf_warning_data", list(group = g))
    }
    known <- !is.na(s_res)

    # ---- calibration factors: factor_c = pop_c / sum(init_weight in c) --------
    iw_g <- iw[sel]
    denom <- tapply(iw_g[known], s_res[known], sum)
    common <- intersect(names(pop_by_res), names(denom))
    factor <- stats::setNames(rep(NA_real_, length(common)), common)
    factor[common] <- pop_by_res[common] / denom[common]

    w <- rep(NA_real_, length(sel))
    w[known] <- iw_g[known] * factor[s_res[known]]
    # respondents in a resolved cell that received no population (only via flag
    # path where its pop was withheld) get factor NA -> weight 0
    w[is.na(w)] <- 0

    # ---- province-total constraint (requirement 7) ---------------------------
    target_total <- target$groups[[g]]$total - pop_flagged
    realized     <- sum(w)
    dev          <- abs(realized - target_total) / target_total
    if (dev > tol)
      wf_abort(sprintf("Group '%s': province-total constraint violated (realized %.6g vs target %.6g, dev %.2e). This indicates an internal bug.",
                       g, realized, target_total, dev),
               "wf_error_internal", list(group = g, dev = dev))

    cv <- stats::sd(w[known]) / mean(w[known])
    res_rows[[g]] <- data.frame(
      id = ids[sel], group = g, resolved_cell = s_res,
      weight = w, feature = 1 / w, stringsAsFactors = FALSE)

    # ---- audit report: one row per ORIGINAL population cell ------------------
    cellw_mean <- tapply(w[known], s_res[known], mean)
    rep_g <- data.frame(
      group = g, jdf[, dvars, drop = FALSE], pop = jdf$pop,
      n_sample = res$supp_final, ladder_level_used = res$level_used,
      resolved_cell = res$resolved,
      granularity_used = res$granularity_used,
      orphan = res$orphan,
      redistributed_to = NA_character_, pop_moved = 0,
      final_cell_weight_mean = cellw_mean[res$resolved],
      stringsAsFactors = FALSE)
    if (!is.null(res$redist_log)) {
      for (r in seq_len(nrow(res$redist_log))) {
        hit <- rep_g$resolved_cell == res$redist_log$receiving_cell[r] &
               rep_g$n_sample == 0
        # mark the specific orphan rows that moved
      }
      # simpler: annotate orphan rows directly from the log by matching original
      om <- match(res$redist_log$orphan_cell,
                  vapply(seq_len(nrow(rep_g)),
                         function(i) paste(rep_g[i, dvars], collapse = "\r"),
                         character(1)))
    }
    reports[[g]] <- rep_g
    maps[[g]] <- data.frame(
      group = g, raw_cell = res$raw_key, resolved_cell = res$resolved,
      level = res$level_used, stringsAsFactors = FALSE)

    logs[[g]] <- data.frame(
      group = g, n = length(sel),
      n_cells_raw = nrow(jdf),
      n_cells_resolved = length(unique(res$resolved)),
      granularity_used = res$granularity_used,
      n_orphan_cells = if (is.null(res$redist_log)) 0L else nrow(res$redist_log),
      pop_redistributed = if (is.null(res$redist_log)) 0 else
        sum(jdf$pop[match(res$redist_log$orphan_cell,
            vapply(seq_len(nrow(jdf)),
                   function(i) paste(jdf[i, dvars], collapse = "\r"),
                   character(1)))], na.rm = TRUE),
      total_target = target_total, total_realized = realized,
      total_dev = dev, deff = round(1 + cv^2, 3),
      stringsAsFactors = FALSE)
  }

  structure(list(
    data = do.call(rbind, res_rows),
    log  = do.call(rbind, logs),
    cell_report = do.call(rbind, reports),
    collapse_map = structure(
      list(map = do.call(rbind, maps),
           settings = list(min_cell = min_cell, granularity = granularity)),
      class = "wf_poststrat_plan"),
    provenance = list(
      method = "poststrat", dims = dvars, by = target$by,
      min_cell = min_cell, granularity = granularity, empty_cell = empty_cell,
      init_weight = init_weight, ladder_levels = ladder$n_levels,
      created = t0, elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = "0.2.0")
  ), class = "wf_weights")
}

# augment the 0.1 print method with a post-strat line (dispatch by method field)
print.wf_weights <- function(x, ...) {
  cat(sprintf("<wf_weights>  %d unit(s) in %d group(s); method: %s\n",
              nrow(x$data), nrow(x$log),
              if (is.null(x$provenance$method)) "raking" else x$provenance$method))
  cat(sprintf("  weight range [%.4g, %.4g]; elapsed %.2fs\n",
              min(x$data$weight), max(x$data$weight), x$provenance$elapsed))
  if (!is.null(x$provenance$method) && x$provenance$method == "poststrat") {
    lg <- x$log
    cat(sprintf("  cells: %d raw -> %d resolved (median); groups degraded to province: %d\n",
                stats::median(lg$n_cells_raw),
                stats::median(lg$n_cells_resolved),
                sum(lg$granularity_used == "province")))
    cat(sprintf("  max province-total deviation: %.2e\n", max(lg$total_dev)))
  }
  invisible(x)
}
