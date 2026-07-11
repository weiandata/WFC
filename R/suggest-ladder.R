#' Draft a post-stratification collapse ladder
#'
#' Examines worst-group category support and proposes adjacent category merges
#' in the explicit level order declared by [wf_dims()]. The result is a draft
#' for review; no input is modified and no merge is applied automatically.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param dims A `wf_dims` object with explicit ordered levels for every
#'   calibration dimension.
#' @param min_cell Minimum required unweighted sample support in every group.
#'
#' @return A `wf_ladder_draft` containing reviewable levels and a validated
#'   `wf_collapse_ladder` in `$ladder`.
#' @export
#' @examples
#' data(wfc_example)
#' target <- wf_target_population(
#'   wfc_example$population,
#'   c(gender = "gender", age = "age"),
#'   "count",
#'   wfc_example$dims,
#'   by = "province"
#' )
#' wf_suggest_ladder(wfc_example$sample, target, wfc_example$dims, min_cell = 25)
wf_suggest_ladder <- function(sample, target, dims, min_cell = 5) {
  if (!is.data.frame(sample) || nrow(sample) == 0) {
    wf_abort("`sample` must be a non-empty data frame.", "wf_error_input")
  }
  if (!inherits(target, "wf_target")) {
    wf_abort("`target` must be a wf_target object.", "wf_error_input")
  }
  if (!inherits(dims, "wf_dims")) {
    wf_abort("`dims` must be a wf_dims object.", "wf_error_input")
  }
  dvars <- names(dims$vars)
  if (!identical(target$dims, dvars)) {
    wf_abort(
      "`dims` must declare the target dimensions in the same order.",
      "wf_error_schema",
      list(target_dims = target$dims, dims = dvars)
    )
  }
  if (any(vapply(dims$vars, is.null, logical(1)))) {
    wf_abort(
      paste(
        "wf_suggest_ladder() requires explicit ordered levels for every",
        "dimension; inferred levels cannot define defensible adjacency."
      ),
      "wf_error_input"
    )
  }
  if (length(min_cell) != 1 || !is.finite(min_cell) || min_cell < 1 ||
      min_cell != as.integer(min_cell)) {
    wf_abort("`min_cell` must be a positive integer.", "wf_error_input")
  }

  .require_cols(sample, c(target$by, dvars), "sample")
  gkey <- .wf_group_keys(sample, target$by)
  if (any(is.na(gkey))) {
    wf_abort(
      "Sample grouping keys must not contain NA when drafting a ladder.",
      "wf_error_schema"
    )
  }
  groups <- names(target$groups)
  missing_groups <- setdiff(groups, unique(gkey))
  if (length(missing_groups) > 0) {
    wf_abort(
      sprintf(
        "Cannot draft a ladder: target group(s) have no sample rows: %s.",
        paste(missing_groups, collapse = ", ")
      ),
      "wf_error_feasibility",
      list(groups = missing_groups)
    )
  }

  t0 <- Sys.time()
  drafts <- list()
  affected <- numeric()
  support_before <- list()

  for (d in dvars) {
    values <- .chr(sample[[d]])
    levels <- dims$vars[[d]]
    unknown <- setdiff(unique(values[!is.na(values)]), levels)
    if (length(unknown) > 0) {
      wf_abort(
        sprintf(
          "Sample dimension '%s' contains undeclared level(s): %s.",
          d,
          paste(unknown, collapse = ", ")
        ),
        "wf_error_schema",
        list(dim = d, levels = unknown)
      )
    }

    support <- matrix(
      0L,
      nrow = length(levels),
      ncol = length(groups),
      dimnames = list(levels, groups)
    )
    for (g in groups) {
      for (level in levels) {
        support[level, g] <- sum(gkey == g & !is.na(values) & values == level)
      }
    }
    support_before[[d]] <- support

    partition <- as.list(levels)
    partition_worst <- function(parts) {
      vapply(parts, function(categories) {
        min(colSums(support[categories, , drop = FALSE]))
      }, numeric(1))
    }
    worst <- partition_worst(partition)
    if (all(worst >= min_cell)) {
      next
    }

    while (any(worst < min_cell)) {
      if (length(partition) == 1) {
        wf_abort(
          sprintf(
            "Dimension '%s' cannot reach min_cell = %d even after full collapse.",
            d,
            as.integer(min_cell)
          ),
          "wf_error_feasibility",
          list(dim = d, min_cell = min_cell, support = worst)
        )
      }
      i <- which.min(worst)[1]
      neighbour <- if (i == 1) {
        2L
      } else if (i == length(partition)) {
        i - 1L
      } else if (worst[i - 1L] <= worst[i + 1L]) {
        i - 1L
      } else {
        i + 1L
      }
      left <- min(i, neighbour)
      right <- max(i, neighbour)
      partition[[left]] <- c(partition[[left]], partition[[right]])
      partition[[right]] <- NULL
      worst <- partition_worst(partition)
    }

    merged <- partition[lengths(partition) > 1]
    if (length(merged) == 0) {
      next
    }
    merged_names <- vapply(merged, paste, character(1), collapse = "+")
    map <- stats::setNames(
      rep(merged_names, lengths(merged)),
      unlist(merged, use.names = FALSE)
    )
    drafts[[d]] <- map
    affected[[d]] <- sum(!is.na(values) & values %in% names(map)) /
      sum(!is.na(values))
  }

  order_dims <- if (length(affected) > 0) {
    names(sort(affected, method = "radix"))
  } else {
    character()
  }
  levels <- lapply(order_dims, function(d) {
    stats::setNames(list(drafts[[d]]), d)
  })
  if (length(levels) > 0) {
    names(levels) <- paste0("level", seq_along(levels))
  }
  affected <- affected[order_dims]
  ladder <- do.call(wf_collapse_ladder, c(list(dims), levels))

  structure(
    list(
      levels = levels,
      affected_share = affected,
      support_before = support_before,
      min_cell = as.integer(min_cell),
      ladder = ladder,
      provenance = list(
        method = "suggest_ladder",
        by = target$by,
        dims = dvars,
        created = t0,
        package_version = .wf_package_version()
      )
    ),
    class = "wf_ladder_draft"
  )
}

#' Print a collapse-ladder draft
#'
#' @param x A `wf_ladder_draft` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_ladder_draft <- function(x, ...) {
  cat(sprintf(
    "<wf_ladder_draft> %d level(s); min_cell = %d (review before use)\n",
    length(x$levels),
    x$min_cell
  ))
  for (level in names(x$levels)) {
    d <- names(x$levels[[level]])
    map <- x$levels[[level]][[d]]
    cat(sprintf(
      "  %s [%s, %.1f%% affected]: %s\n",
      level,
      d,
      100 * x$affected_share[[d]],
      paste(sprintf("%s->%s", names(map), map), collapse = ", ")
    ))
  }
  invisible(x)
}
