#' Validate and resolve top count for influence output.
#'
#' @param top Requested top count.
#' @keywords internal
#' @noRd
.wf_influence_top <- function(top) {
  if (length(top) != 1 || !is.numeric(top) || !is.finite(top) ||
      top < 1 || top != as.integer(top)) {
    wf_abort("`top` must be a positive integer.", "wf_error_input")
  }
  as.integer(top)
}

#' Compute a design effect from weights.
#'
#' @param weight Numeric weights.
#' @keywords internal
#' @noRd
.wf_influence_deff <- function(weight) {
  if (length(weight) < 2 || mean(weight) <= 0) {
    return(NA_real_)
  }
  1 + (stats::sd(weight) / mean(weight))^2
}

#' Add optional target-margin influence shares.
#'
#' @param table Influence table.
#' @param w Weight object.
#' @param sample Sample data.
#' @param target Target object.
#' @param id Sample ID column.
#' @keywords internal
#' @noRd
.wf_influence_margin_share <- function(table, w, sample, target, id) {
  if (is.null(sample) || is.null(target)) {
    table$max_margin_share <- NA_real_
    table$max_margin_dim <- NA_character_
    table$max_margin_category <- NA_character_
    return(table)
  }
  if (!inherits(target, "wf_target")) {
    wf_abort("`target` must be NULL or a wf_target object.", "wf_error_input")
  }
  if (!is.data.frame(sample) || nrow(sample) == 0) {
    wf_abort("`sample` must be NULL or a non-empty data frame.", "wf_error_input")
  }
  if (!.wf_is_string(id)) {
    wf_abort(
      "`id` must be supplied when `sample` and `target` are used.",
      "wf_error_input"
    )
  }
  .require_cols(sample, c(id, target$by, target$dims), "sample")
  order <- .wf_match_unit_ids(
    sample,
    id,
    w$data$id,
    "`w$data$id`",
    "wf_influence()"
  )
  aligned <- sample
  aligned$.wf_weight <- w$data$weight[order]
  aligned$.wf_group <- w$data$group[order]

  max_share <- numeric(nrow(aligned))
  max_dim <- character(nrow(aligned))
  max_cat <- character(nrow(aligned))
  for (i in seq_len(nrow(aligned))) {
    group <- aligned$.wf_group[[i]]
    best_share <- NA_real_
    best_dim <- NA_character_
    best_cat <- NA_character_
    for (dim in target$dims) {
      category <- .chr(aligned[[dim]][[i]])
      target_margin <- target$groups[[group]]$margins[[dim]][[category]]
      if (!is.null(target_margin) && is.finite(target_margin) &&
          target_margin > 0) {
        share <- aligned$.wf_weight[[i]] / target_margin
        if (is.na(best_share) || share > best_share) {
          best_share <- share
          best_dim <- dim
          best_cat <- category
        }
      }
    }
    max_share[[i]] <- best_share
    max_dim[[i]] <- best_dim
    max_cat[[i]] <- best_cat
  }

  sample_key <- .chr(aligned[[id]])
  idx <- match(table$id, sample_key)
  table$max_margin_share <- max_share[idx]
  table$max_margin_dim <- max_dim[idx]
  table$max_margin_category <- max_cat[idx]
  table
}

#' Diagnose high-influence calibrated units
#'
#' Reports the units that contribute most to weight instability. The core
#' diagnostics are per-unit weight ratio to the group mean, share of the
#' group's squared-weight mass, and leave-one-out design effect for the top
#' units. When `sample` and `target` are supplied, WFC also reports the largest
#' share of any target margin represented by that unit.
#'
#' @param w A `wf_weights` object with unit IDs.
#' @param target Optional `wf_target` for margin-share diagnostics.
#' @param sample Optional sample data frame aligned by `id`.
#' @param id Sample ID column required when `sample` and `target` are supplied.
#' @param top Number of highest-ratio units for which leave-one-out design
#'   effects are computed and printed.
#'
#' @return A `wf_influence` object with a `$table` data frame.
#' @export
wf_influence <- function(w, target = NULL, sample = NULL, id = NULL, top = 20) {
  if (!inherits(w, "wf_weights")) {
    wf_abort("`w` must be a wf_weights object.", "wf_error_input")
  }
  if (!is.data.frame(w$data) || nrow(w$data) == 0 ||
      !all(c("id", "group", "weight") %in% names(w$data))) {
    wf_abort(
      "`w$data` must contain id, group, and weight columns.",
      "wf_error_schema"
    )
  }
  top <- .wf_influence_top(top)
  ids <- .chr(w$data$id)
  if (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids)) {
    wf_abort(
      "Influence diagnostics require non-missing unique unit IDs.",
      "wf_error_schema"
    )
  }
  weight <- as.numeric(w$data$weight)
  if (anyNA(weight) || any(!is.finite(weight)) || any(weight <= 0)) {
    wf_abort(
      "Influence diagnostics require finite positive weights.",
      "wf_error_input"
    )
  }

  rows <- lapply(split(seq_len(nrow(w$data)), .chr(w$data$group)), function(idx) {
    part_weight <- weight[idx]
    group_deff <- .wf_influence_deff(part_weight)
    data.frame(
      id = ids[idx],
      group = .chr(w$data$group[idx]),
      weight = part_weight,
      ratio_to_mean = part_weight / mean(part_weight),
      deff_share = part_weight^2 / sum(part_weight^2),
      deff_group = group_deff,
      deff_loo = NA_real_,
      deff_drop_if_removed = NA_real_,
      stringsAsFactors = FALSE
    )
  })
  table <- do.call(rbind, rows)
  table <- table[order(-table$ratio_to_mean, -table$deff_share), , drop = FALSE]
  row.names(table) <- NULL
  table <- .wf_influence_margin_share(table, w, sample, target, id)

  n_top <- min(top, nrow(table))
  for (i in seq_len(n_top)) {
    group <- table$group[[i]]
    group_idx <- which(.chr(w$data$group) == group)
    drop_idx <- which(ids == table$id[[i]])
    loo_idx <- setdiff(group_idx, drop_idx)
    loo_deff <- .wf_influence_deff(weight[loo_idx])
    table$deff_loo[[i]] <- loo_deff
    table$deff_drop_if_removed[[i]] <- table$deff_group[[i]] - loo_deff
  }

  structure(
    list(
      table = table,
      top = n_top,
      provenance = list(
        method = "influence",
        source_method = w$provenance$method,
        top = n_top,
        created = Sys.time(),
        package_version = .wf_package_version()
      )
    ),
    class = "wf_influence"
  )
}

#' Print influence diagnostics
#'
#' @param x A `wf_influence` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_influence <- function(x, ...) {
  cat(sprintf("<wf_influence> top %d high-ratio unit(s)\n", x$top))
  cols <- c(
    "id", "group", "weight", "ratio_to_mean", "deff_share",
    "deff_group", "deff_loo", "deff_drop_if_removed"
  )
  if ("max_margin_share" %in% names(x$table) &&
      any(is.finite(x$table$max_margin_share))) {
    cols <- c(cols, "max_margin_share", "max_margin_dim", "max_margin_category")
  }
  print(utils::head(x$table[cols], x$top), row.names = FALSE, digits = 4)
  invisible(x)
}
