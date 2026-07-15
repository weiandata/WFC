#' Aggregate design support into deterministic cells.
#'
#' @param data Design data frame.
#' @param boundary_values Character boundary key per row.
#' @param dims Calibration dimension names.
#' @param base_weight Base-weight vector.
#' @keywords internal
#' @noRd
.wf_cell_table <- function(data, boundary_values, dims, base_weight) {
  cell_data <- data.frame(
    boundary = .chr(boundary_values),
    lapply(data[dims], .chr),
    n = rep(1, nrow(data)),
    base_weight = base_weight,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  cells <- stats::aggregate(
    cell_data[c("n", "base_weight")],
    cell_data[c("boundary", dims)],
    sum
  )
  order_args <- c(cells[c("boundary", dims)], list(method = "radix"))
  cells <- cells[do.call(order, order_args), , drop = FALSE]
  row.names(cells) <- NULL
  cells
}

#' Build original-to-final category maps for every boundary.
#'
#' @param design A `wf_design_data` object.
#' @param target A `wf_verified_target` object.
#' @param dims A `wf_dims` object.
#' @param boundary_values Character boundary key per design row.
#' @keywords internal
#' @noRd
.wf_initial_category_maps <- function(design, target, dims, boundary_values) {
  rows <- list()
  index <- 0L
  for (boundary in names(target$groups)) {
    selected <- boundary_values == boundary
    for (dim in names(dims$vars)) {
      categories <- unique(c(
        dims$vars[[dim]],
        names(target$groups[[boundary]]$margins[[dim]]),
        .chr(design$data[[dim]][selected])
      ))
      categories <- categories[!is.na(categories)]
      for (category in categories) {
        index <- index + 1L
        rows[[index]] <- data.frame(
          boundary = boundary,
          dim = dim,
          category_before = category,
          category_after = category,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  maps <- do.call(rbind, rows)
  row.names(maps) <- NULL
  maps
}

#' Apply stored category maps to design data.
#'
#' @param data Design data frame.
#' @param boundary_values Character boundary key per row.
#' @param maps Stored original-to-final category maps.
#' @param dims Calibration dimension names.
#' @keywords internal
#' @noRd
.wf_map_design_categories <- function(data, boundary_values, maps, dims) {
  out <- data
  for (boundary in unique(boundary_values)) {
    selected <- boundary_values == boundary
    for (dim in dims) {
      map <- maps[maps$boundary == boundary & maps$dim == dim, , drop = FALSE]
      values <- .chr(out[[dim]][selected])
      matched <- match(values, map$category_before)
      hit <- !is.na(matched)
      values[hit] <- map$category_after[matched[hit]]
      out[[dim]][selected] <- values
    }
  }
  out
}

#' Apply stored category maps to target margins.
#'
#' @param target A `wf_target` object.
#' @param maps Stored original-to-final category maps.
#' @keywords internal
#' @noRd
.wf_map_target_categories <- function(target, maps) {
  out <- target
  for (boundary in names(out$groups)) {
    for (dim in out$dims) {
      margin <- out$groups[[boundary]]$margins[[dim]]
      map <- maps[maps$boundary == boundary & maps$dim == dim, , drop = FALSE]
      categories <- names(margin)
      matched <- match(categories, map$category_before)
      hit <- !is.na(matched)
      categories[hit] <- map$category_after[matched[hit]]
      out$groups[[boundary]]$margins[[dim]] <- .wf_margin_vector(
        tapply(as.numeric(margin), categories, sum)
      )
    }
  }
  if (!is.null(out$joint)) {
    for (boundary in names(out$joint)) {
      joint <- out$joint[[boundary]]
      for (dim in out$dims) {
        map <- maps[
          maps$boundary == boundary & maps$dim == dim,
          ,
          drop = FALSE
        ]
        categories <- .chr(joint[[dim]])
        matched <- match(categories, map$category_before)
        hit <- !is.na(matched)
        categories[hit] <- map$category_after[matched[hit]]
        joint[[dim]] <- categories
      }
      out$joint[[boundary]] <- stats::aggregate(
        joint["pop"],
        joint[out$dims],
        sum
      )
    }
  }
  .wf_validate_target(out)
  out
}

#' Calculate a conservative marginal weight-ratio projection.
#'
#' @param data Mapped design data.
#' @param boundary_values Character boundary key per row.
#' @param base_weight Base-weight vector.
#' @param target Mapped target.
#' @param dims Calibration dimension names.
#' @param boundary Boundary to evaluate.
#' @keywords internal
#' @noRd
.wf_boundary_weight_ratio <- function(data, boundary_values, base_weight,
                                      target, dims, boundary) {
  selected <- boundary_values == boundary
  if (!any(selected)) {
    return(Inf)
  }
  sample_total <- sum(base_weight[selected])
  target_total <- target$groups[[boundary]]$total
  ratios <- numeric()

  for (dim in dims) {
    sample_margin <- tapply(
      base_weight[selected],
      .chr(data[[dim]][selected]),
      sum
    )
    target_margin <- target$groups[[boundary]]$margins[[dim]]
    categories <- union(names(sample_margin), names(target_margin))
    sample_share <- stats::setNames(rep(0, length(categories)), categories)
    target_share <- sample_share
    sample_share[names(sample_margin)] <- sample_margin / sample_total
    target_share[names(target_margin)] <- target_margin / target_total

    forward <- target_share / sample_share
    reverse <- sample_share / target_share
    ratios <- c(ratios, forward, reverse)
  }

  ratios[is.nan(ratios)] <- 1
  max(ratios)
}

#' Update all original categories currently represented by one category.
#'
#' @param maps Category map table.
#' @param boundary Boundary key.
#' @param dim Dimension name.
#' @param from Current category to absorb.
#' @param to Current category that remains.
#' @keywords internal
#' @noRd
.wf_merge_category <- function(maps, boundary, dim, from, to) {
  selected <- maps$boundary == boundary & maps$dim == dim &
    maps$category_after == from
  maps$category_after[selected] <- to
  maps
}

#' Evaluate one boundary under a category map.
#'
#' @param design_data Original design data frame.
#' @param boundary_values Character boundary key per row.
#' @param base_weight Base-weight vector.
#' @param target Original target.
#' @param maps Category map table.
#' @param dims Calibration dimension names.
#' @param boundary Boundary key.
#' @param min_cell Minimum supported cell size.
#' @keywords internal
#' @noRd
.wf_boundary_state <- function(design_data, boundary_values, base_weight,
                               target, maps, dims, boundary, min_cell) {
  mapped_data <- .wf_map_design_categories(
    design_data,
    boundary_values,
    maps,
    dims
  )
  mapped_target <- .wf_map_target_categories(target, maps)
  selected <- boundary_values == boundary
  cells <- .wf_cell_table(
    mapped_data[selected, , drop = FALSE],
    boundary_values[selected],
    dims,
    base_weight[selected]
  )
  ratio <- .wf_boundary_weight_ratio(
    mapped_data,
    boundary_values,
    base_weight,
    mapped_target,
    dims,
    boundary
  )
  list(
    data = mapped_data,
    target = mapped_target,
    cells = cells,
    thin = sum(cells$n < min_cell),
    ratio = ratio
  )
}

#' Select a deterministic ordered-adjacency merge.
#'
#' @param state Current boundary state.
#' @param maps Current category maps.
#' @param design_data Original design data frame.
#' @param boundary_values Character boundary key per row.
#' @param base_weight Base-weight vector.
#' @param target Original target.
#' @param dims A `wf_dims` object.
#' @param boundary Boundary key.
#' @param min_cell Minimum supported cell size.
#' @param max_weight_ratio Maximum permitted projected ratio.
#' @keywords internal
#' @noRd
.wf_choose_adjacency_merge <- function(state, maps, design_data,
                                       boundary_values, base_weight, target,
                                       dims, boundary, min_cell,
                                       max_weight_ratio) {
  candidates <- list()
  index <- 0L
  current_bad <- state$thin + as.integer(state$ratio > max_weight_ratio)

  for (dim in names(dims$vars)) {
    map <- maps[maps$boundary == boundary & maps$dim == dim, , drop = FALSE]
    current <- unique(map$category_after)
    declared <- dims$vars[[dim]]
    ranks <- vapply(current, function(category) {
      originals <- map$category_before[map$category_after == category]
      positions <- match(originals, declared)
      if (all(is.na(positions))) Inf else min(positions, na.rm = TRUE)
    }, numeric(1))
    current <- current[order(ranks, current, method = "radix")]
    if (length(current) < 2L) {
      next
    }

    pairs <- cbind(current[-length(current)], current[-1L])
    directions <- rbind(pairs, pairs[, 2:1, drop = FALSE])
    for (i in seq_len(nrow(directions))) {
      from <- directions[i, 1]
      to <- directions[i, 2]
      candidate_maps <- .wf_merge_category(maps, boundary, dim, from, to)
      candidate_state <- .wf_boundary_state(
        design_data,
        boundary_values,
        base_weight,
        target,
        candidate_maps,
        names(dims$vars),
        boundary,
        min_cell
      )
      candidate_bad <- candidate_state$thin +
        as.integer(candidate_state$ratio > max_weight_ratio)
      improves <- candidate_bad < current_bad ||
        candidate_state$ratio < state$ratio
      if (!improves) {
        next
      }

      selected <- boundary_values == boundary & state$data[[dim]] == from
      index <- index + 1L
      candidates[[index]] <- list(
        maps = candidate_maps,
        state = candidate_state,
        improvement = current_bad - candidate_bad,
        moved = sum(selected),
        distance = 1,
        distortion = sum(base_weight[selected]),
        dim = dim,
        from = from,
        to = to
      )
    }
  }

  if (!length(candidates)) {
    return(NULL)
  }
  score <- data.frame(
    improvement = vapply(candidates, `[[`, numeric(1), "improvement"),
    moved = vapply(candidates, `[[`, numeric(1), "moved"),
    distance = vapply(candidates, `[[`, numeric(1), "distance"),
    distortion = vapply(candidates, `[[`, numeric(1), "distortion"),
    dim = vapply(candidates, `[[`, character(1), "dim"),
    from = vapply(candidates, `[[`, character(1), "from"),
    to = vapply(candidates, `[[`, character(1), "to"),
    stringsAsFactors = FALSE
  )
  selected <- order(
    -score$improvement,
    score$moved,
    score$distance,
    score$distortion,
    score$dim,
    score$from,
    score$to,
    method = "radix"
  )[1]
  candidates[[selected]]
}

#' Calculate the identity of a stored cell merge plan.
#'
#' @param plan Cell plan fields.
#' @keywords internal
#' @noRd
.wf_cell_plan_identity <- function(plan) {
  .wf_sha256_object(plan[setdiff(names(plan), c("created", "identity"))])
}

#' Plan deterministic, outcome-blind support-cell merging
#'
#' Uses only declared design fields, external target margins, ordered dimension
#' levels, and an optional explicit collapse ladder. Study outcomes and custom
#' scoring callbacks are not accepted by this interface.
#'
#' @param design A `wf_design_data` object.
#' @param target A non-demo `wf_verified_target` object.
#' @param dims A `wf_dims` object.
#' @param min_cell Minimum observed count in every retained joint design cell.
#' @param max_weight_ratio Maximum conservative marginal target-to-design ratio.
#' @param boundary Optional grouping column; defaults to the target grouping.
#' @param ladder Optional explicit `wf_collapse_ladder`.
#'
#' @return A reviewable `wf_cell_merge_plan`. No weights are computed.
#' @export
wf_plan_cells <- function(design, target, dims, min_cell = 5,
                          max_weight_ratio = 4, boundary = target$by,
                          ladder = NULL) {
  if (!inherits(design, "wf_design_data")) {
    .wf_safety_abort(
      "design_object_required",
      "`design` must be a wf_design_data object.",
      "design"
    )
  }
  if (!identical(design$identity, .wf_design_identity(design$data, design$roles))) {
    .wf_safety_abort(
      "design_identity_invalid",
      "Design data have changed since their identity was recorded.",
      "design"
    )
  }
  if (!inherits(target, "wf_verified_target") || isTRUE(target$demo_only)) {
    .wf_safety_abort(
      "verified_target_required",
      "`target` must be a non-demo verified external target.",
      "target"
    )
  }
  if (!identical(target$identity, .wf_verified_target_identity(target))) {
    .wf_safety_abort(
      "target_identity_invalid",
      "Target data have changed since their identity was recorded.",
      "target"
    )
  }
  if (!inherits(dims, "wf_dims") ||
      !identical(names(dims$vars), target$dims)) {
    .wf_safety_abort(
      "target_dimensions_mismatch",
      "Declared dimensions must exactly match the verified target.",
      "dims"
    )
  }
  if (length(min_cell) != 1L || !is.finite(min_cell) ||
      min_cell < 1 || min_cell != as.integer(min_cell)) {
    .wf_safety_abort(
      "min_cell_invalid",
      "`min_cell` must be a positive integer.",
      "min_cell"
    )
  }
  if (length(max_weight_ratio) != 1L || !is.finite(max_weight_ratio) ||
      max_weight_ratio <= 1) {
    .wf_safety_abort(
      "max_weight_ratio_invalid",
      "`max_weight_ratio` must be a finite number greater than one.",
      "max_weight_ratio"
    )
  }
  if (!is.null(boundary) && !.wf_is_string(boundary)) {
    .wf_safety_abort(
      "merge_boundary_invalid",
      "`boundary` must be one column name or NULL.",
      "boundary"
    )
  }
  if (!identical(boundary, target$by)) {
    .wf_safety_abort(
      "merge_boundary_mismatch",
      "Cell merging must remain inside the verified target boundary.",
      "boundary"
    )
  }
  if (!is.null(ladder) &&
      (!inherits(ladder, "wf_collapse_ladder") ||
       !identical(ladder$dims, names(dims$vars)))) {
    .wf_safety_abort(
      "collapse_ladder_mismatch",
      "`ladder` must match the declared dimensions.",
      "ladder"
    )
  }

  required <- c(boundary, names(dims$vars))
  .require_cols(design$data, required, "design data")
  boundary_values <- .wf_group_keys(design$data, boundary)
  missing_boundaries <- setdiff(names(target$groups), unique(boundary_values))
  if (length(missing_boundaries)) {
    wf_abort(
      "No allowed cell merge can create support in a missing boundary.",
      "wf_error_feasibility",
      .wf_safety_payload(
        "merge_boundary_unsupported",
        "blocking",
        boundary,
        list(boundaries = missing_boundaries),
        "collect_boundary_sample"
      )
    )
  }

  base_weight <- if (is.null(design$roles$base_weight)) {
    rep(1, nrow(design$data))
  } else {
    design$data[[design$roles$base_weight]]
  }
  dim_names <- names(dims$vars)
  maps <- .wf_initial_category_maps(
    design,
    target,
    dims,
    boundary_values
  )
  reasons <- list()
  reason_index <- 0L

  for (boundary_key in names(target$groups)) {
    state <- .wf_boundary_state(
      design$data,
      boundary_values,
      base_weight,
      target,
      maps,
      dim_names,
      boundary_key,
      min_cell
    )
    ladder_level <- 0L
    merge_count <- 0L

    while (state$thin > 0L || state$ratio > max_weight_ratio) {
      if (!is.null(ladder)) {
        ladder_level <- ladder_level + 1L
        if (ladder_level > ladder$n_levels) {
          candidate <- NULL
        } else {
          step <- ladder$steps[[ladder_level]]
          changed <- FALSE
          for (dim in names(step)) {
            for (from in names(step[[dim]])) {
              to <- unname(step[[dim]][[from]])
              current_hit <- maps$boundary == boundary_key &
                maps$dim == dim & maps$category_after == from
              if (any(current_hit) && !identical(from, to)) {
                maps <- .wf_merge_category(
                  maps,
                  boundary_key,
                  dim,
                  from,
                  to
                )
                changed <- TRUE
                reason_index <- reason_index + 1L
                reasons[[reason_index]] <- data.frame(
                  boundary = boundary_key,
                  step = names(ladder$steps)[ladder_level],
                  dim = dim,
                  from = from,
                  to = to,
                  reason = "explicit_ladder",
                  stringsAsFactors = FALSE
                )
              }
            }
          }
          if (changed) {
            merge_count <- merge_count + 1L
            state <- .wf_boundary_state(
              design$data,
              boundary_values,
              base_weight,
              target,
              maps,
              dim_names,
              boundary_key,
              min_cell
            )
            next
          }
          next
        }
      } else {
        candidate <- .wf_choose_adjacency_merge(
          state,
          maps,
          design$data,
          boundary_values,
          base_weight,
          target,
          dims,
          boundary_key,
          min_cell,
          max_weight_ratio
        )
      }

      if (is.null(candidate)) {
        wf_abort(
          sprintf(
            "No allowed partition satisfies min_cell=%d and max_weight_ratio=%s inside boundary '%s'.",
            as.integer(min_cell),
            format(max_weight_ratio),
            boundary_key
          ),
          "wf_error_feasibility",
          .wf_safety_payload(
            "cell_partition_infeasible",
            "blocking",
            boundary,
            list(
              boundary = boundary_key,
              thin_cells = state$thin,
              projected_max_weight_ratio = state$ratio
            ),
            "revise_declared_ladder_or_design"
          )
        )
      }

      maps <- candidate$maps
      state <- candidate$state
      merge_count <- merge_count + 1L
      reason_index <- reason_index + 1L
      reasons[[reason_index]] <- data.frame(
        boundary = boundary_key,
        step = paste0("adjacency_", merge_count),
        dim = candidate$dim,
        from = candidate$from,
        to = candidate$to,
        reason = "declared_order_adjacency",
        stringsAsFactors = FALSE
      )
    }
  }

  mapped_data <- .wf_map_design_categories(
    design$data,
    boundary_values,
    maps,
    dim_names
  )
  mapped_target <- .wf_map_target_categories(target, maps)
  cells_before <- .wf_cell_table(
    design$data,
    boundary_values,
    dim_names,
    base_weight
  )
  cells_after <- .wf_cell_table(
    mapped_data,
    boundary_values,
    dim_names,
    base_weight
  )
  projected_ratios <- vapply(names(target$groups), function(boundary_key) {
    .wf_boundary_weight_ratio(
      mapped_data,
      boundary_values,
      base_weight,
      mapped_target,
      dim_names,
      boundary_key
    )
  }, numeric(1))

  map <- data.frame(
    boundary_before = boundary_values,
    boundary_after = boundary_values,
    stringsAsFactors = FALSE
  )
  for (dim in dim_names) {
    map[[paste0(dim, "_before")]] <- .chr(design$data[[dim]])
    map[[paste0(dim, "_after")]] <- .chr(mapped_data[[dim]])
  }
  map <- unique(map)
  row.names(map) <- NULL

  changed <- vapply(seq_len(nrow(design$data)), function(i) {
    any(vapply(dim_names, function(dim) {
      !identical(.chr(design$data[[dim]][i]), .chr(mapped_data[[dim]][i]))
    }, logical(1)))
  }, logical(1))
  reason_table <- if (length(reasons)) {
    do.call(rbind, reasons)
  } else {
    data.frame(
      boundary = character(),
      step = character(),
      dim = character(),
      from = character(),
      to = character(),
      reason = character(),
      stringsAsFactors = FALSE
    )
  }
  row.names(reason_table) <- NULL

  plan <- list(
    cells_before = cells_before,
    cells_after = cells_after,
    map = map,
    category_maps = maps,
    reasons = reason_table,
    affected_share = mean(changed),
    unresolved_cells = cells_after[cells_after$n < min_cell, , drop = FALSE],
    projected_max_weight_ratio = max(projected_ratios),
    input_identities = list(design = design$identity, target = target$identity),
    settings = list(
      dims = dim_names,
      min_cell = as.integer(min_cell),
      max_weight_ratio = max_weight_ratio,
      boundary = boundary,
      ladder = ladder
    ),
    created = .wf_iso_time(),
    package_version = .wf_package_version()
  )
  plan$identity <- .wf_cell_plan_identity(plan)
  class(plan) <- "wf_cell_merge_plan"
  plan
}

#' Apply an already reviewed cell plan exactly as stored.
#'
#' @param design A `wf_design_data` object matching the plan.
#' @param target A `wf_verified_target` object matching the plan.
#' @param plan A `wf_cell_merge_plan` object.
#' @keywords internal
#' @noRd
.wf_apply_cell_plan <- function(design, target, plan) {
  if (!inherits(plan, "wf_cell_merge_plan")) {
    .wf_safety_abort(
      "cell_plan_required",
      "`plan` must be a wf_cell_merge_plan object.",
      "plan"
    )
  }
  if (!identical(plan$identity, .wf_cell_plan_identity(plan))) {
    .wf_safety_abort(
      "cell_plan_identity_invalid",
      "The reviewed cell plan has changed since its identity was recorded.",
      "plan"
    )
  }
  if (!inherits(design, "wf_design_data") ||
      !identical(design$identity, plan$input_identities$design) ||
      !identical(design$identity, .wf_design_identity(design$data, design$roles))) {
    .wf_safety_abort(
      "cell_plan_design_changed",
      "Design data no longer match the reviewed cell plan.",
      "design"
    )
  }
  if (!inherits(target, "wf_verified_target") ||
      !identical(target$identity, plan$input_identities$target) ||
      !identical(target$identity, .wf_verified_target_identity(target))) {
    .wf_safety_abort(
      "cell_plan_target_changed",
      "Target data no longer match the reviewed cell plan.",
      "target"
    )
  }

  boundary_values <- .wf_group_keys(design$data, plan$settings$boundary)
  mapped_data <- .wf_map_design_categories(
    design$data,
    boundary_values,
    plan$category_maps,
    plan$settings$dims
  )
  mapped_target <- .wf_map_target_categories(target, plan$category_maps)
  mapped_target <- .wf_verified_target(
    mapped_target,
    target$evidence,
    target$source_type
  )
  mapped_target$meta$cell_plan_identity <- plan$identity
  mapped_design <- wf_prepare_design(
    mapped_data,
    id = design$roles$id,
    calibration = design$roles$calibration,
    base_weight = design$roles$base_weight,
    strata = design$roles$strata,
    clusters = design$roles$clusters,
    fpc = design$roles$fpc
  )

  list(design = mapped_design, target = mapped_target)
}

#' Print an outcome-blind cell merge plan
#'
#' @param x A `wf_cell_merge_plan` object.
#' @param ... Reserved for future use.
#'
#' @return `x`, invisibly.
#' @export
print.wf_cell_merge_plan <- function(x, ...) {
  cat("<wf_cell_merge_plan>\n")
  cat(" Cells: ", nrow(x$cells_before), " -> ", nrow(x$cells_after), "\n", sep = "")
  cat(" Affected share: ", format(round(x$affected_share, 4)), "\n", sep = "")
  cat(
    " Projected max weight ratio: ",
    format(round(x$projected_max_weight_ratio, 4)),
    "\n",
    sep = ""
  )
  cat(" Identity: ", x$identity, "\n", sep = "")
  invisible(x)
}
