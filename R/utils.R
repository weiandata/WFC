#' Normalize calibration keys to trimmed character values.
#'
#' @param x Vector to normalize.
#' @return A character vector.
#' @keywords internal
#' @noRd
.chr <- function(x) {
  trimws(as.character(x))
}

#' Require columns in a data frame.
#'
#' @param df Data frame to check.
#' @param cols Required column names.
#' @param what Human-readable data source name.
#' @keywords internal
#' @noRd
.require_cols <- function(df, cols, what) {
  miss <- setdiff(cols, names(df))
  if (length(miss) > 0) {
    wf_abort(sprintf(
      "%s is missing column(s): %s",
      what,
      paste(miss, collapse = ", ")
    ), "wf_error_schema", list(missing = miss))
  }
}

#' Create a validated target object.
#'
#' @param mode Target mode.
#' @param by Grouping variable.
#' @param dims Dimension names.
#' @param groups Target groups.
#' @param meta Provenance metadata.
#' @keywords internal
#' @noRd
.wf_new_target <- function(mode, by, dims, groups, meta = list(), joint = NULL) {
  tgt <- structure(
    list(mode = mode, by = by, dims = dims, groups = groups, meta = meta, joint = joint),
    class = "wf_target"
  )
  .wf_validate_target(tgt)
  tgt
}

#' Validate target invariants.
#'
#' @param tgt Target object.
#' @param tol Relative tolerance.
#' @keywords internal
#' @noRd
.wf_validate_target <- function(tgt, tol = 1e-8) {
  for (g in names(tgt$groups)) {
    gr <- tgt$groups[[g]]
    if (!is.finite(gr$total) || gr$total <= 0) {
      wf_abort(sprintf(
        "Group '%s': target total must be positive and finite.",
        g
      ), "wf_error_input", list(group = g, total = gr$total))
    }
    for (d in tgt$dims) {
      m <- gr$margins[[d]]
      if (is.null(m) || is.null(names(m))) {
        wf_abort(sprintf(
          "Group '%s', dim '%s': margins missing or unnamed.",
          g,
          d
        ), "wf_error_internal", list(group = g, dim = d))
      }
      if (any(!is.finite(m)) || any(m < 0)) {
        wf_abort(sprintf(
          "Group '%s', dim '%s': margins must be finite and >= 0.",
          g,
          d
        ), "wf_error_input", list(group = g, dim = d))
      }
      if (abs(sum(m) - gr$total) > tol * gr$total) {
        wf_abort(sprintf(
          "Group '%s', dim '%s': margins sum to %.6g but total is %.6g. %s",
          g,
          d,
          sum(m),
          gr$total,
          "Additivity is required so IPF preserves the group total."
        ), "wf_error_input", list(group = g, dim = d))
      }
    }
  }
  invisible(TRUE)
}

#' Resolve group keys.
#'
#' @param df Data frame.
#' @param by Grouping variable name or `NULL`.
#' @param by_key Optional group key column or function.
#' @keywords internal
#' @noRd
.wf_group_keys <- function(df, by, by_key = NULL) {
  if (!is.null(by_key)) {
    if (is.function(by_key)) {
      return(.chr(by_key(df)))
    }
    .require_cols(df, by_key, "population data")
    return(.chr(df[[by_key]]))
  }
  if (is.null(by)) {
    return(rep("_all_", nrow(df)))
  }
  .require_cols(df, by, "data")
  .chr(df[[by]])
}

#' Rescale target groups.
#'
#' @param groups Target group list.
#' @param scale Scale mode.
#' @param sample_n Per-group sample sizes.
#' @param totals Custom totals.
#' @keywords internal
#' @noRd
.wf_scale_groups <- function(groups, scale, sample_n = NULL, totals = NULL) {
  if (scale == "population") {
    return(groups)
  }
  for (g in names(groups)) {
    new_total <-
      if (scale == "sample") {
        if (is.null(sample_n) || is.na(sample_n[g])) {
          wf_abort(sprintf(
            "scale='sample' needs the sample: no size found for group '%s'.",
            g
          ), "wf_error_input", list(group = g))
        }
        sample_n[g]
      } else {
        if (is.null(totals) || is.na(totals[g])) {
          wf_abort(sprintf(
            "scale='custom' requires totals['%s'].",
            g
          ), "wf_error_input", list(group = g))
        }
        totals[g]
      }
    f <- new_total / groups[[g]]$total
    groups[[g]]$total <- unname(new_total)
    groups[[g]]$margins <- lapply(groups[[g]]$margins, function(m) m * f)
  }
  groups
}

#' Sum weights by integer group index.
#'
#' @param w Weight vector.
#' @param idx Integer group indices.
#' @param K Number of groups.
#' @keywords internal
#' @noRd
.grp_sum <- function(w, idx, K) {
  out <- numeric(K)
  rs <- rowsum(w, idx)
  out[as.integer(rownames(rs))] <- rs[, 1]
  out
}

#' Return the loaded package version for provenance records.
#'
#' @return The installed package version as a character scalar, or the
#'   development fallback when the package is not installed.
#' @keywords internal
#' @noRd
.wf_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("WFC")),
    error = function(e) "dev"
  )
}

#' Resolve the number of workers for optional fork parallelism.
#'
#' @keywords internal
#' @noRd
.wf_parallel_workers <- function(n, use_parallel) {
  if (!isTRUE(use_parallel) || n <= 1L) {
    return(1L)
  }
  if (identical(.Platform$OS.type, "windows")) {
    message("parallel=TRUE uses forked parallelism; Windows falls back to serial execution.")
    return(1L)
  }
  cores <- getOption("wfc.parallel.cores", NULL)
  if (is.null(cores)) {
    cores <- parallel::detectCores(logical = FALSE)
    cores <- if (is.na(cores)) 2L else max(1L, cores - 1L)
  }
  cores <- suppressWarnings(as.integer(cores))
  if (length(cores) != 1L || is.na(cores) || cores < 1L) {
    cores <- 1L
  }
  min(n, cores)
}

#' Start a cli progress bar when requested and available.
#'
#' @keywords internal
#' @noRd
.wf_progress_start <- function(n, progress, label) {
  if (!isTRUE(progress) || n <= 0L ||
      !requireNamespace("cli", quietly = TRUE)) {
    return(NULL)
  }
  tryCatch(
    cli::cli_progress_bar(name = label, total = n, clear = FALSE),
    error = function(e) NULL
  )
}

#' Update an optional cli progress bar.
#'
#' @keywords internal
#' @noRd
.wf_progress_tick <- function(id, inc = 1L) {
  if (!is.null(id)) {
    tryCatch(
      cli::cli_progress_update(id = id, inc = inc),
      error = function(e) NULL
    )
  }
}

#' Finish an optional cli progress bar.
#'
#' @keywords internal
#' @noRd
.wf_progress_done <- function(id) {
  if (!is.null(id)) {
    tryCatch(
      cli::cli_progress_done(id = id),
      error = function(e) NULL
    )
  }
}

#' Evaluate one mapped task and retain classed warnings/errors.
#'
#' @keywords internal
#' @noRd
.wf_eval_task <- function(x, fun) {
  warnings <- list()
  value <- tryCatch(
    withCallingHandlers(
      fun(x),
      warning = function(w) {
        warnings[[length(warnings) + 1L]] <<- w
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) e
  )
  list(ok = !inherits(value, "error"), value = value, warnings = warnings)
}

#' Normalize a child-process result into the internal task envelope.
#'
#' @keywords internal
#' @noRd
.wf_normalize_task_result <- function(x) {
  if (inherits(x, "try-error")) {
    return(list(
      ok = FALSE,
      value = simpleError(as.character(x)),
      warnings = list()
    ))
  }
  if (is.list(x) && !is.null(x$ok) && !is.null(x$warnings)) {
    return(x)
  }
  list(
    ok = FALSE,
    value = simpleError("Parallel worker returned an invalid result."),
    warnings = list()
  )
}

#' Re-emit task warnings and return its value, or rethrow its error.
#'
#' @keywords internal
#' @noRd
.wf_task_value <- function(x) {
  x <- .wf_normalize_task_result(x)
  for (w in x$warnings) {
    warning(w)
  }
  if (!isTRUE(x$ok)) {
    stop(x$value)
  }
  x$value
}

#' Run a list map with optional fork parallelism and progress reporting.
#'
#' @keywords internal
#' @noRd
.wf_parallel_map <- function(x, fun, use_parallel = FALSE, progress = FALSE,
                             label = "WFC tasks") {
  n <- length(x)
  workers <- .wf_parallel_workers(n, use_parallel)
  pb <- .wf_progress_start(n, progress, label)
  on.exit(.wf_progress_done(pb), add = TRUE)

  eval_index <- function(i) .wf_eval_task(x[[i]], fun)
  if (workers > 1L && !is.null(pb)) {
    raw <- .wf_parallel_map_poll(seq_len(n), eval_index, workers, pb)
  } else if (workers > 1L) {
    raw <- parallel::mclapply(seq_len(n), eval_index, mc.cores = workers)
    .wf_progress_tick(pb, n)
  } else {
    raw <- vector("list", n)
    for (i in seq_len(n)) {
      raw[[i]] <- eval_index(i)
      .wf_progress_tick(pb)
    }
  }

  out <- lapply(raw, .wf_task_value)
  attr(out, "workers") <- workers
  attr(out, "parallel") <- workers > 1L
  out
}

#' Forked map implementation that can tick progress as jobs finish.
#'
#' @keywords internal
#' @noRd
.wf_parallel_map_poll <- function(indices, eval_index, workers, pb) {
  out <- vector("list", length(indices))
  active <- list()
  next_pos <- 1L

  launch <- function() {
    i <- indices[[next_pos]]
    proc <- parallel::mcparallel(eval_index(i), silent = TRUE)
    active[[as.character(proc$pid)]] <<- list(index = i, proc = proc)
    next_pos <<- next_pos + 1L
  }

  while (next_pos <= length(indices) && length(active) < workers) {
    launch()
  }
  while (length(active) > 0L) {
    collected <- parallel::mccollect(
      lapply(active, `[[`, "proc"),
      wait = FALSE,
      timeout = 0.1
    )
    if (is.null(collected) || length(collected) == 0L) {
      Sys.sleep(0.05)
      next
    }
    for (pid in names(collected)) {
      job <- active[[pid]]
      out[[job$index]] <- .wf_normalize_task_result(collected[[pid]])
      active[[pid]] <- NULL
      .wf_progress_tick(pb)
      if (next_pos <= length(indices)) {
        launch()
      }
    }
  }
  out
}

#' Convert grouped sums to a named numeric vector.
#'
#' @param x One-dimensional grouped-sum result.
#' @return A named numeric vector.
#' @keywords internal
#' @noRd
.wf_margin_vector <- function(x) {
  stats::setNames(as.numeric(x), names(x))
}
