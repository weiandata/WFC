#' Return the loaded package version for provenance.
#'
#' @keywords internal
#' @noRd
.wf_compose_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("WFC")),
    error = function(e) "0.4.0"
  )
}

#' Validate a compose normalization mode.
#'
#' @param normalize Requested normalization mode.
#' @keywords internal
#' @noRd
.wf_compose_normalize <- function(normalize) {
  supported <- c("none", "mean1", "sum")
  if (length(normalize) != 1 || is.na(normalize) || !normalize %in% supported) {
    shown <- if (length(normalize) == 0) "<empty>" else as.character(normalize[[1]])
    wf_abort(
      sprintf(
        "Unsupported compose normalization '%s'. Supported modes: none, mean1, sum.",
        shown
      ),
      "wf_error_input",
      list(normalize = normalize)
    )
  }
  normalize
}

#' Label a composition stage.
#'
#' @param index Stage index.
#' @param stage_names Names from the `...` list.
#' @keywords internal
#' @noRd
.wf_compose_stage_label <- function(index, stage_names) {
  if (!is.null(stage_names) && length(stage_names) >= index && nzchar(stage_names[[index]])) {
    return(stage_names[[index]])
  }
  paste0("stage_", index)
}

#' Resolve the ID column for composition.
#'
#' @param stages List of `wf_weights` objects.
#' @param id Optional user-supplied ID column.
#' @keywords internal
#' @noRd
.wf_compose_id_col <- function(stages, id) {
  if (!is.null(id)) {
    if (length(id) != 1 || is.na(id) || !nzchar(id)) {
      wf_abort("`id` must be a single non-empty column name.", "wf_error_input")
    }
    return(id)
  }

  has_id <- vapply(stages, function(stage) {
    is.data.frame(stage$data) && "id" %in% names(stage$data)
  }, logical(1))
  if (all(has_id)) {
    return("id")
  }
  if (!any(has_id)) {
    return(NULL)
  }

  wf_abort(
    "Either every stage must have an id column or no stage may have one. Supply `id` when using a different shared ID column.",
    "wf_error_input",
    list(has_id = has_id)
  )
}

#' Validate one stage and extract compose columns.
#'
#' @param stage A `wf_weights` object.
#' @param index Stage index.
#' @param label Stage label.
#' @param id_col ID column name or `NULL`.
#' @keywords internal
#' @noRd
.wf_compose_stage_data <- function(stage, index, label, id_col) {
  if (!inherits(stage, "wf_weights")) {
    wf_abort(
      sprintf("Compose stage %d ('%s') must be a wf_weights object.", index, label),
      "wf_error_input",
      list(stage = index)
    )
  }
  if (!is.data.frame(stage$data)) {
    wf_abort(
      sprintf("Compose stage %d ('%s') must contain a data frame in `$data`.", index, label),
      "wf_error_input",
      list(stage = index)
    )
  }

  required <- c("group", "weight")
  if (!is.null(id_col)) {
    required <- c(id_col, required)
  }
  .require_cols(stage$data, required, sprintf("compose stage %d data", index))

  weight <- stage$data$weight
  if (any(is.na(weight)) || any(!is.finite(weight)) || any(weight <= 0)) {
    wf_abort(
      sprintf("Compose stage %d ('%s') has non-finite or non-positive weights.", index, label),
      "wf_error_input",
      list(stage = index)
    )
  }

  group <- .chr(stage$data$group)
  if (any(is.na(group)) || any(group == "")) {
    wf_abort(
      sprintf("Compose stage %d ('%s') has missing group values.", index, label),
      "wf_error_input",
      list(stage = index)
    )
  }

  ids <- NULL
  if (!is.null(id_col)) {
    ids <- .chr(stage$data[[id_col]])
    if (any(is.na(ids)) || any(ids == "")) {
      wf_abort(
        sprintf("Compose stage %d ('%s') has missing ID values.", index, label),
        "wf_error_input",
        list(stage = index)
      )
    }
    dup <- unique(ids[duplicated(ids)])
    if (length(dup) > 0) {
      wf_abort(
        sprintf(
          "Compose stage %d ('%s') has duplicated ID value(s): %s.",
          index,
          label,
          paste(utils::head(dup, 5), collapse = ", ")
        ),
        "wf_error_input",
        list(stage = index, ids = dup)
      )
    }
  }

  list(
    id = ids,
    group = group,
    weight = as.numeric(weight),
    stage = stage
  )
}

#' Build a per-stage provenance summary.
#'
#' @param part Validated stage data.
#' @param index Stage index.
#' @param label Stage label.
#' @keywords internal
#' @noRd
.wf_compose_stage_summary <- function(part, index, label) {
  list(
    index = index,
    name = label,
    row_count = length(part$weight),
    group_count = length(unique(part$group)),
    total_weight = sum(part$weight),
    mean_weight = mean(part$weight),
    min_weight = min(part$weight),
    max_weight = max(part$weight),
    provenance = part$stage$provenance
  )
}

#' Build a composition log compatible with wf_diagnose().
#'
#' @param data Composed weight data.
#' @param stage_count Number of composed stages.
#' @keywords internal
#' @noRd
.wf_compose_log <- function(data, stage_count) {
  rows <- lapply(split(data, data$group), function(group_data) {
    data.frame(
      group = group_data$group[[1]],
      n = nrow(group_data),
      total_weight = sum(group_data$weight),
      mean_weight = mean(group_data$weight),
      min_weight = min(group_data$weight),
      max_weight = max(group_data$weight),
      stage_count = stage_count,
      iterations = NA_integer_,
      converged = TRUE,
      trimmed = 0L,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Compose multiple weighting stages
#'
#' Multiplies compatible `wf_weights` objects into one auditable pipeline result.
#'
#' @param ... Two or more `wf_weights` objects.
#' @param id Optional shared ID column in each stage's `$data`. If `NULL`,
#'   `wf_compose()` uses `data$id` when every stage has it, or row order when no
#'   stage has an ID column.
#' @param normalize Weight normalization mode: `"none"`, `"mean1"`, or `"sum"`.
#'
#' @return A composed `wf_weights` object.
#' @export
#'
#' @examples
#' stage1 <- structure(
#'   list(
#'     data = data.frame(id = c("r1", "r2"), group = "A", weight = c(2, 3)),
#'     log = data.frame(group = "A"),
#'     achieved = NULL,
#'     provenance = list(method = "stage1")
#'   ),
#'   class = "wf_weights"
#' )
#' stage2 <- stage1
#' stage2$data$weight <- c(0.5, 2)
#' stage2$provenance$method <- "stage2"
#' wf_compose(stage1, stage2)
wf_compose <- function(..., id = NULL, normalize = c("none", "mean1", "sum")) {
  t0 <- Sys.time()
  normalize <- if (missing(normalize)) "none" else .wf_compose_normalize(normalize)
  stages <- list(...)
  stage_names <- names(stages)

  if (length(stages) < 2) {
    wf_abort("`wf_compose()` requires at least two wf_weights stages.", "wf_error_input")
  }
  for (i in seq_along(stages)) {
    label <- .wf_compose_stage_label(i, stage_names)
    if (!inherits(stages[[i]], "wf_weights")) {
      wf_abort(
        sprintf("Compose stage %d ('%s') must be a wf_weights object.", i, label),
        "wf_error_input",
        list(stage = i)
      )
    }
  }

  id_col <- .wf_compose_id_col(stages, id)
  parts <- lapply(seq_along(stages), function(i) {
    .wf_compose_stage_data(
      stages[[i]],
      i,
      .wf_compose_stage_label(i, stage_names),
      id_col
    )
  })

  base <- parts[[1]]
  if (is.null(id_col)) {
    row_counts <- vapply(parts, function(part) length(part$weight), integer(1))
    if (length(unique(row_counts)) != 1) {
      wf_abort(
        "Row-order composition requires every stage to have the same row count.",
        "wf_error_input",
        list(row_counts = row_counts)
      )
    }
    out_id <- .chr(seq_len(row_counts[[1]]))
    out_group <- base$group
    product <- base$weight
    for (i in 2:length(parts)) {
      mismatch <- which(parts[[i]]$group != out_group)
      if (length(mismatch) > 0) {
        wf_abort(
          sprintf("Compose stage %d has group assignments that differ from stage 1.", i),
          "wf_error_input",
          list(stage = i, ids = out_id[utils::head(mismatch, 5)])
        )
      }
      product <- product * parts[[i]]$weight
    }
    id_source <- "row_order"
  } else {
    out_id <- base$id
    out_group <- base$group
    product <- base$weight
    for (i in 2:length(parts)) {
      missing <- setdiff(out_id, parts[[i]]$id)
      extra <- setdiff(parts[[i]]$id, out_id)
      if (length(missing) > 0 || length(extra) > 0) {
        wf_abort(
          sprintf("Compose stage %d has a different ID set from stage 1.", i),
          "wf_error_input",
          list(stage = i, missing = missing, extra = extra)
        )
      }
      idx <- match(out_id, parts[[i]]$id)
      group_i <- parts[[i]]$group[idx]
      mismatch <- which(group_i != out_group)
      if (length(mismatch) > 0) {
        wf_abort(
          sprintf("Compose stage %d has group assignments that differ from stage 1.", i),
          "wf_error_input",
          list(stage = i, ids = out_id[utils::head(mismatch, 5)])
        )
      }
      product <- product * parts[[i]]$weight[idx]
    }
    id_source <- id_col
  }

  normalization_factor <- switch(
    normalize,
    none = 1,
    mean1 = 1 / mean(product),
    sum = sum(base$weight) / sum(product)
  )
  final_weight <- product * normalization_factor
  out_data <- data.frame(
    id = out_id,
    group = out_group,
    weight = final_weight,
    feature = 1 / final_weight,
    stringsAsFactors = FALSE
  )

  structure(
    list(
      data = out_data,
      log = .wf_compose_log(out_data, length(parts)),
      achieved = NULL,
      provenance = list(
        method = "compose",
        mode = "compose",
        stages = lapply(seq_along(parts), function(i) {
          .wf_compose_stage_summary(
            parts[[i]],
            i,
            .wf_compose_stage_label(i, stage_names)
          )
        }),
        compose = list(
          normalize = normalize,
          normalization_factor = normalization_factor,
          id = id_source,
          stage_count = length(parts),
          created = t0,
          elapsed = as.numeric(Sys.time() - t0, units = "secs"),
          package_version = .wf_compose_package_version()
        )
      )
    ),
    class = "wf_weights"
  )
}
