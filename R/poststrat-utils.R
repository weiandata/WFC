#' Build joint cell keys.
#'
#' @param mat Character matrix containing dimension columns.
#' @param dvars Dimension column names.
#' @keywords internal
#' @noRd
.wf_cell_key <- function(mat, dvars) {
  do.call(paste, c(lapply(dvars, function(d) mat[, d]), sep = "\r"))
}

#' Split joint cell keys back into dimension columns.
#'
#' @param keys Cell keys built by `.wf_cell_key()`.
#' @param dvars Dimension column names.
#' @keywords internal
#' @noRd
.wf_split_key <- function(keys, dvars) {
  parts <- do.call(rbind, strsplit(keys, "\r", fixed = TRUE))
  df <- as.data.frame(parts, stringsAsFactors = FALSE)
  names(df) <- dvars
  df
}

#' Apply cumulative collapse ladder maps.
#'
#' @param mat Character matrix containing dimension columns.
#' @param ladder A `wf_collapse_ladder` object.
#' @param lv Highest ladder level to apply.
#' @keywords internal
#' @noRd
.wf_apply_ladder <- function(mat, ladder, lv) {
  if (lv == 0) {
    return(mat)
  }
  for (k in seq_len(lv)) {
    step <- ladder$steps[[k]]
    for (d in names(step)) {
      map <- step[[d]]
      col <- mat[, d]
      hit <- !is.na(col) & col %in% names(map)
      col[hit] <- map[col[hit]]
      mat[, d] <- col
    }
  }
  mat
}

#' Validate post-stratification arguments.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param min_cell Minimum sample count per resolved cell.
#' @param ladder A `wf_collapse_ladder` object.
#' @keywords internal
#' @noRd
.wf_check_poststrat_args <- function(sample, target, min_cell, ladder) {
  if (is.null(target$joint)) {
    wf_abort(
      "Target has no joint cell table. Rebuild with wf_target_population(..., keep_joint = TRUE).",
      "wf_error_schema"
    )
  }
  if (!inherits(ladder, "wf_collapse_ladder")) {
    wf_abort("`ladder` must be a wf_collapse_ladder object.", "wf_error_input")
  }
  if (missing(min_cell) || length(min_cell) != 1 || !is.finite(min_cell) ||
      min_cell < 1 || min_cell != as.integer(min_cell)) {
    wf_abort("`min_cell` must be a single integer >= 1.", "wf_error_input")
  }
  .require_cols(sample, c(target$dims, target$by), "sample")
  if (!identical(sort(ladder$dims), sort(target$dims))) {
    wf_abort(
      "Ladder dimensions do not match target dimensions.",
      "wf_error_schema",
      list(ladder = ladder$dims, target = target$dims)
    )
  }
  invisible(TRUE)
}

#' Resolve post-stratification cells for one group.
#'
#' @param smat Sample dimension matrix.
#' @param jdf Joint target data frame for one group.
#' @param dvars Dimension names.
#' @param ladder Collapse ladder.
#' @param min_cell Minimum sample count.
#' @param granularity Requested granularity.
#' @param group Group key.
#' @keywords internal
#' @noRd
.wf_resolve_group <- function(smat, jdf, dvars, ladder, min_cell,
                              granularity, group) {
  jmat <- as.matrix(jdf[, dvars, drop = FALSE])
  raw_pop_key <- .wf_cell_key(jmat, dvars)

  max_lv <- ladder$n_levels
  s_keys <- lapply(0:max_lv, function(lv) {
    .wf_cell_key(.wf_apply_ladder(smat, ladder, lv), dvars)
  })
  s_counts <- lapply(s_keys, table)
  p_keys <- lapply(0:max_lv, function(lv) {
    .wf_cell_key(.wf_apply_ladder(jmat, ladder, lv), dvars)
  })

  n_raw <- nrow(jdf)
  level_used <- integer(n_raw)
  resolved <- character(n_raw)
  gran_used <- granularity

  support_at <- function(lv, cellkeys) {
    tb <- s_counts[[lv + 1]]
    as.integer(ifelse(cellkeys %in% names(tb), tb[cellkeys], 0L))
  }

  if (granularity == "adaptive") {
    settle <- rep(0L, n_raw)
    repeat {
      before <- settle
      keys <- vapply(seq_len(n_raw), function(i) {
        p_keys[[settle[i] + 1]][i]
      }, character(1))
      supp <- vapply(seq_len(n_raw), function(i) {
        support_at(settle[i], keys[i])
      }, integer(1))
      under <- supp < min_cell & settle < max_lv
      if (any(under)) {
        bad <- unique(keys[under])
        lift <- keys %in% bad & settle < max_lv
        settle[lift] <- settle[lift] + 1L
      }

      for (L in seq_len(max_lv)) {
        kL <- p_keys[[L + 1]]
        hasL <- tapply(settle >= L, kL, any)
        lift <- as.logical(hasL[kL]) & settle < L
        if (any(lift)) {
          settle[lift] <- L
        }
      }

      if (identical(settle, before)) {
        break
      }
    }

    final_keys <- vapply(seq_len(n_raw), function(i) {
      p_keys[[settle[i] + 1]][i]
    }, character(1))
    final_supp <- vapply(seq_len(n_raw), function(i) {
      support_at(settle[i], final_keys[i])
    }, integer(1))
    if (any(final_supp < min_cell)) {
      gran_used <- "province"
    } else {
      level_used <- settle
      resolved <- final_keys
    }
  }

  if (gran_used == "province") {
    chosen <- NA_integer_
    for (lv in 0:max_lv) {
      supp <- support_at(lv, p_keys[[lv + 1]])
      if (all(supp >= min_cell)) {
        chosen <- lv
        break
      }
    }
    if (is.na(chosen)) {
      chosen <- max_lv
    }
    level_used <- rep(chosen, n_raw)
    resolved <- p_keys[[chosen + 1]]
  }

  supp_final <- vapply(seq_len(n_raw), function(i) {
    support_at(level_used[i], resolved[i])
  }, integer(1))
  orphan <- supp_final == 0

  list(
    raw_key = raw_pop_key,
    level_used = level_used,
    resolved = resolved,
    supp_final = supp_final,
    orphan = orphan,
    granularity_used = gran_used,
    s_keys = s_keys,
    p_keys = p_keys,
    jmat = jmat
  )
}

#' Redistribute orphan cells to supported ancestors.
#'
#' @param res Resolution result from `.wf_resolve_group()`.
#' @param min_cell Minimum sample count.
#' @param group Group key.
#' @keywords internal
#' @noRd
.wf_redistribute <- function(res, min_cell, group) {
  redist <- list()
  max_lv <- length(res$s_keys) - 1

  support_at_final <- function(res, k) {
    tb <- table(res$s_keys[[res$level_used[k] + 1]])
    key <- res$resolved[k]
    if (key %in% names(tb)) {
      as.integer(tb[key])
    } else {
      0L
    }
  }

  for (i in which(res$orphan)) {
    moved <- FALSE
    lv0 <- res$level_used[i]
    if (lv0 < max_lv) {
      for (lv in (lv0 + 1):max_lv) {
        anc <- res$p_keys[[lv + 1]][i]
        tb <- table(res$s_keys[[lv + 1]])
        if (anc %in% names(tb) && tb[anc] > 0) {
          redist[[length(redist) + 1]] <- data.frame(
            group = group,
            raw_cell = res$raw_key[i],
            orphan_cell = res$resolved[i],
            receiving_cell = anc,
            ancestor_level = lv,
            stringsAsFactors = FALSE
          )
          res$resolved[i] <- anc
          res$level_used[i] <- lv
          res$orphan[i] <- FALSE
          moved <- TRUE
          break
        }
      }
    }

    if (!moved) {
      supported <- which(!res$orphan)
      if (length(supported) == 0) {
        wf_abort(
          sprintf(
            "Group '%s': no resolved cell has any sample support; cannot post-stratify this group.",
            group
          ),
          "wf_error_feasibility",
          list(group = group)
        )
      }
      counts <- vapply(supported, function(k) support_at_final(res, k), integer(1))
      recv <- res$resolved[supported[which.max(counts)]]
      redist[[length(redist) + 1]] <- data.frame(
        group = group,
        raw_cell = res$raw_key[i],
        orphan_cell = res$resolved[i],
        receiving_cell = recv,
        ancestor_level = -1L,
        stringsAsFactors = FALSE
      )
      res$resolved[i] <- recv
      res$orphan[i] <- FALSE
    }
  }

  res$redist_log <- if (length(redist) > 0) do.call(rbind, redist) else NULL
  res
}
