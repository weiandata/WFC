#' Confirm one guided workflow decision.
#'
#' @param prompt Localized prompt text.
#' @keywords internal
#' @noRd
.wf_autoweigh_confirm <- function(prompt) {
  answer <- tolower(trimws(readline(prompt)))
  answer %in% c("y", "yes")
}

#' Run a guided and auditable weighting workflow
#'
#' Builds or accepts a canonical target, enforces the precheck discipline,
#' applies only declared collapse remediations, optionally recommends and
#' applies raking trim bounds, then returns weights, diagnostics, a manager
#' report, and a machine-readable decision ledger.
#'
#' @param sample Non-empty sample data frame.
#' @param population A raw population data frame or ready `wf_target`.
#' @param dims A `wf_dims` declaration.
#' @param key_map Named population-column mapping required for raw population
#'   data.
#' @param count Population count column required for raw population data.
#' @param by Optional grouping variable used when building a raw target.
#' @param id Optional unique unit identifier column.
#' @param method Calibration method. `"auto"` selects post-stratification only
#'   when both `ladder` and `min_cell` are supplied; otherwise it selects
#'   raking.
#' @param ladder Reviewed `wf_collapse_ladder`, or a `wf_ladder_draft` whose
#'   validated `$ladder` should be used for post-stratification.
#' @param min_cell Positive post-stratification cell-size threshold.
#' @param bounds Two-element bounds for logit calibration.
#' @param trim Raking trim control: `"auto"`, `NULL`, or two numeric bounds.
#' @param max_deff Maximum design effect accepted by automatic trimming.
#' @param max_residual Maximum margin residual accepted by automatic trimming.
#' @param interactive Whether declared collapse and finite trim recommendations
#'   require confirmation.
#' @param lang Output language for narration and the manager report.
#' @param ... Method controls. Raking accepts `caps`, `lo`, `na`,
#'   `trim_cycles`, `tol`, `max_iter`, and `init_weight`; logit accepts `na`,
#'   `tol`, `max_iter`, and `init_weight`; post-stratification accepts
#'   `granularity`, `empty_cell`, `tol`, and `init_weight`.
#'
#' @return A `wf_autoweigh_result` containing weights, diagnostics, report,
#'   ordered ledger, aligned artifacts, final sample and target, selected
#'   method, and normalized language.
#' @export
wf_autoweigh <- function(sample, population, dims,
                          key_map = NULL, count = NULL,
                          by = NULL, id = NULL,
                          method = c("auto", "raking", "poststrat", "logit"),
                          ladder = NULL, min_cell = NULL,
                          bounds = c(0.3, 3),
                          trim = "auto",
                          max_deff = 6, max_residual = 0.02,
                          interactive = base::interactive(),
                          lang = NULL, ...) {
  method <- tryCatch(
    match.arg(method),
    error = function(e) {
      wf_abort(
        "`method` must be one of auto, raking, poststrat, or logit.",
        "wf_error_input"
      )
    }
  )
  language <- .wf_lang(lang)

  if (!is.data.frame(sample) || nrow(sample) == 0) {
    wf_abort("`sample` must be a non-empty data frame.", "wf_error_input")
  }
  if (!inherits(dims, "wf_dims")) {
    wf_abort("`dims` must be a wf_dims object.", "wf_error_input")
  }
  if (length(interactive) != 1 || !is.logical(interactive) ||
      is.na(interactive)) {
    wf_abort("`interactive` must be TRUE or FALSE.", "wf_error_input")
  }
  if (length(max_deff) != 1 || !is.numeric(max_deff) ||
      !is.finite(max_deff) || max_deff <= 0) {
    wf_abort("`max_deff` must be a positive finite number.", "wf_error_input")
  }
  if (length(max_residual) != 1 || !is.numeric(max_residual) ||
      !is.finite(max_residual) || max_residual < 0) {
    wf_abort(
      "`max_residual` must be a non-negative finite number.",
      "wf_error_input"
    )
  }

  dots <- list(...)
  if (length(dots) > 0 &&
      (is.null(names(dots)) || any(!nzchar(names(dots))))) {
    wf_abort("All arguments in `...` must be named.", "wf_error_input")
  }
  if ("precheck" %in% names(dots)) {
    wf_abort(
      "`precheck` is owned by wf_autoweigh() and cannot be overridden.",
      "wf_error_input"
    )
  }

  selected_method <- if (method == "auto") {
    if (!is.null(ladder) && !is.null(min_cell)) "poststrat" else "raking"
  } else {
    method
  }
  allowed_dots <- switch(
    selected_method,
    raking = c(
      "caps", "lo", "na", "trim_cycles", "tol", "max_iter",
      "init_weight"
    ),
    logit = c("na", "tol", "max_iter", "init_weight"),
    poststrat = c("granularity", "empty_cell", "tol", "init_weight")
  )
  unknown_dots <- setdiff(names(dots), allowed_dots)
  if (length(unknown_dots) > 0) {
    wf_abort(
      sprintf(
        "Unsupported guided-workflow argument(s) for %s: %s.",
        selected_method,
        paste(unknown_dots, collapse = ", ")
      ),
      "wf_error_input",
      list(arguments = unknown_dots, method = selected_method)
    )
  }

  trim_is_auto <- is.character(trim) && length(trim) == 1 &&
    !is.na(trim) && identical(trim, "auto")
  trim_is_numeric <- is.numeric(trim) && length(trim) == 2 &&
    !anyNA(trim) && all(is.finite(trim)) && all(trim > 0) &&
    trim[[1]] < trim[[2]]
  if (!is.null(trim) && !trim_is_auto && !trim_is_numeric) {
    wf_abort(
      "`trim` must be 'auto', NULL, or two increasing positive bounds.",
      "wf_error_input"
    )
  }
  if (trim_is_numeric && selected_method != "raking") {
    wf_abort("Numeric `trim` bounds apply only to raking.", "wf_error_input")
  }

  target_is_ready <- inherits(population, "wf_target")
  if (!target_is_ready) {
    if (!is.data.frame(population)) {
      wf_abort(
        "`population` must be a data frame or wf_target object.",
        "wf_error_input"
      )
    }
    if (is.null(key_map) || is.null(count)) {
      wf_abort(
        "Raw population data requires both `key_map` and `count`.",
        "wf_error_schema"
      )
    }
  }
  target <- if (target_is_ready) {
    population
  } else {
    wf_target_population(
      population,
      key_map = key_map,
      count = count,
      dims = dims,
      by = by,
      keep_joint = selected_method == "poststrat"
    )
  }
  if (!identical(target$dims, names(dims$vars))) {
    wf_abort(
      "`dims` must declare the target dimensions in the same order.",
      "wf_error_schema",
      list(target_dims = target$dims, dims = names(dims$vars))
    )
  }
  .require_cols(sample, c(id, target$by, target$dims), "sample")

  if (inherits(ladder, "wf_ladder_draft")) {
    ladder <- ladder$ladder
  }
  if (selected_method == "poststrat") {
    valid_min_cell <- length(min_cell) == 1 && is.numeric(min_cell) &&
      is.finite(min_cell) && min_cell >= 1 &&
      min_cell == as.integer(min_cell)
    if (!inherits(ladder, "wf_collapse_ladder") || !valid_min_cell) {
      wf_abort(
        paste(
          "Post-stratification requires a reviewed wf_collapse_ladder and",
          "a positive integer `min_cell`."
        ),
        "wf_error_feasibility"
      )
    }
    if (is.null(target$joint) || length(target$joint) == 0) {
      wf_abort(
        paste(
          "Post-stratification requires a target built with",
          "keep_joint = TRUE."
        ),
        "wf_error_feasibility"
      )
    }
  }

  ledger_rows <- list()
  artifacts <- list()
  note <- function(action, detail_key, ..., artifact = NULL) {
    detail <- .wf_tr(detail_key, ..., lang = language)
    artifact_class <- if (is.null(artifact)) {
      NA_character_
    } else {
      class(artifact)[[1]]
    }
    ledger_rows[[length(ledger_rows) + 1L]] <<- data.frame(
      step = length(ledger_rows) + 1L,
      action = action,
      detail_key = detail_key,
      detail = detail,
      artifact_class = artifact_class,
      time = Sys.time(),
      stringsAsFactors = FALSE
    )
    artifacts <<- c(artifacts, list(artifact))
    message(detail)
    invisible(detail)
  }

  note(
    "start",
    "autoweigh_start",
    nrow(sample),
    length(target$groups),
    length(target$dims)
  )
  note(
    "target",
    if (target_is_ready) "autoweigh_target_ready" else "autoweigh_target_built",
    artifact = target
  )
  note("calibrate", "autoweigh_method", selected_method)

  current_sample <- sample
  current_target <- target
  eligible_collapse_checks <- c(
    "cat_infeasible", "support_thin", "risk_extreme_ratio"
  )
  precheck_na <- if (!is.null(dots$na)) {
    dots$na
  } else if (selected_method == "raking") {
    "fractional"
  } else if (selected_method == "logit") {
    "drop"
  } else {
    "error"
  }
  collapse_round <- 0L
  max_collapse_rounds <- max(
    1L,
    sum(vapply(dims$collapse, length, integer(1))) + 1L
  )

  repeat {
    precheck <- wf_precheck(
      current_sample,
      current_target,
      id = id,
      na = precheck_na
    )
    if (precheck$ok) {
      note(
        "precheck",
        "autoweigh_precheck_ok",
        artifact = precheck
      )
      break
    }

    blocking <- precheck$issues[
      precheck$issues$severity == "error",
      ,
      drop = FALSE
    ]
    note(
      "precheck",
      "autoweigh_precheck_blocked",
      nrow(blocking),
      artifact = precheck
    )
    plan <- wf_suggest_collapse(precheck, dims)
    unresolved_blocking <- plan$unresolved[
      plan$unresolved$severity == "error",
      ,
      drop = FALSE
    ]
    nonremediable <- !blocking$check %in% eligible_collapse_checks
    if (length(plan$maps) == 0 || any(nonremediable) ||
        nrow(unresolved_blocking) > 0 ||
        collapse_round >= max_collapse_rounds) {
      wf_abort(
        paste(
          "Precheck has blocking issues with no applicable declared collapse",
          "remediation. Update wf_dims() or the input data and retry."
        ),
        "wf_error_feasibility",
        list(precheck = precheck, plan = plan)
      )
    }
    if (interactive) {
      print(plan)
      if (!.wf_autoweigh_confirm(.wf_tr(
        "autoweigh_prompt_collapse",
        lang = language
      ))) {
        wf_abort(
          "Declared collapse remediation was declined; weighting stopped.",
          "wf_error_feasibility",
          list(precheck = precheck, plan = plan)
        )
      }
    }

    applied <- wf_apply_collapse(current_sample, current_target, plan)
    current_sample <- applied$sample
    current_target <- applied$target
    collapse_round <- collapse_round + 1L
    for (i in seq_len(nrow(plan$actions))) {
      note(
        "collapse",
        "autoweigh_collapse",
        plan$actions$dim[[i]],
        plan$actions$check[[i]],
        plan$actions$group[[i]],
        artifact = plan
      )
    }
  }

  trim_arg <- NULL
  if (selected_method == "raking" && trim_is_auto) {
    trim_search_args <- c(
      list(
        sample = current_sample,
        target = current_target,
        id = id,
        max_deff = max_deff,
        max_residual = max_residual,
        precheck = FALSE
      ),
      dots
    )
    trim_search <- do.call(wf_auto_trim, trim_search_args)
    recommendation <- trim_search$recommended_cap
    if (is.na(recommendation)) {
      note(
        "trim",
        "autoweigh_trim_no_solution",
        artifact = trim_search
      )
    } else if (!is.finite(recommendation)) {
      note(
        "trim",
        "autoweigh_trim_none",
        artifact = trim_search
      )
    } else {
      if (interactive && !.wf_autoweigh_confirm(.wf_tr(
        "autoweigh_prompt_trim",
        lang = language
      ))) {
        wf_abort(
          "Recommended trim was declined; weighting stopped.",
          "wf_error_feasibility",
          list(auto_trim = trim_search)
        )
      }
      trim_arg <- c(trim_search$criteria$lo, recommendation)
      note(
        "trim",
        "autoweigh_trim_applied",
        recommendation,
        artifact = trim_search
      )
    }
  } else if (selected_method == "raking" && trim_is_numeric) {
    trim_arg <- trim
    note("trim", "autoweigh_trim_manual", trim[[1]], trim[[2]])
  }

  note("calibrate", "autoweigh_calibrating", selected_method)
  engine_dots <- dots[!names(dots) %in% c("caps", "lo")]
  engine_args <- c(
    list(
      sample = current_sample,
      target = current_target,
      method = selected_method,
      id = id
    ),
    switch(
      selected_method,
      raking = list(trim = trim_arg, precheck = FALSE),
      logit = list(bounds = bounds, precheck = FALSE),
      poststrat = list(
        min_cell = as.integer(min_cell),
        ladder = ladder,
        precheck = FALSE
      )
    ),
    engine_dots
  )
  weights <- do.call(wf_calibrate, engine_args)
  diagnostics <- wf_diagnose(weights, target = current_target)
  report <- wf_report(
    weights,
    target = current_target,
    audience = "manager",
    lang = language
  )

  overall_light <- if (any(report$table$light == "red")) {
    "red"
  } else if (any(report$table$light == "yellow")) {
    "yellow"
  } else {
    "green"
  }
  overall_verdict <- .wf_tr(
    paste0("verdict_", overall_light),
    lang = language
  )
  note(
    "done",
    "autoweigh_done",
    nrow(weights$data),
    overall_verdict,
    artifact = report
  )

  ledger <- do.call(rbind, ledger_rows)
  names(artifacts) <- sprintf(
    "step_%03d_%s",
    ledger$step,
    ledger$action
  )
  structure(
    list(
      weights = weights,
      diagnostics = diagnostics,
      report = report,
      ledger = ledger,
      artifacts = artifacts,
      sample = current_sample,
      target = current_target,
      method = selected_method,
      language = language
    ),
    class = "wf_autoweigh_result"
  )
}

#' Print a guided weighting result
#'
#' @param x A `wf_autoweigh_result` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_autoweigh_result <- function(x, ...) {
  cat(sprintf(
    "<wf_autoweigh_result> %s\n",
    .wf_tr("autoweigh_print_header", lang = x$language)
  ))
  cat(sprintf(
    "  %d weight(s); method: %s; %d ledger step(s)\n",
    nrow(x$weights$data),
    x$method,
    nrow(x$ledger)
  ))
  for (i in seq_len(nrow(x$ledger))) {
    cat(sprintf(
      "  [%d] %-9s %s\n",
      x$ledger$step[[i]],
      x$ledger$action[[i]],
      x$ledger$detail[[i]]
    ))
  }
  invisible(x)
}
