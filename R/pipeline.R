#' Test for one non-empty character scalar.
#'
#' @param x Object to test.
#' @keywords internal
#' @noRd
.wf_is_string <- function(x) {
  length(x) == 1 && is.character(x) && !is.na(x) && nzchar(x)
}

#' Format a timestamp for stable provenance.
#'
#' @param x POSIX time.
#' @keywords internal
#' @noRd
.wf_iso_time <- function(x = Sys.time()) {
  format(x, "%Y-%m-%dT%H:%M:%S%z")
}

#' Remove session-specific values before hashing.
#'
#' @param x Object to sanitize.
#' @keywords internal
#' @noRd
.wf_sanitize_for_hash <- function(x) {
  if (inherits(x, "formula")) {
    return(paste(deparse(x), collapse = " "))
  }
  if (inherits(x, "POSIXt")) {
    return(.wf_iso_time(x))
  }
  if (is.environment(x)) {
    return("<environment>")
  }
  if (is.function(x)) {
    return("<function>")
  }
  if (is.factor(x)) {
    return(as.character(x))
  }
  if (is.data.frame(x)) {
    out <- lapply(x, .wf_sanitize_for_hash)
    out$.row_names <- row.names(x)
    return(out)
  }
  if (is.list(x)) {
    return(lapply(x, .wf_sanitize_for_hash))
  }
  x
}

#' Build a dependency-free object hash for provenance.
#'
#' @param x Object to hash.
#' @keywords internal
#' @noRd
.wf_object_hash <- function(x) {
  raw <- serialize(.wf_sanitize_for_hash(x), NULL, version = 2)
  h <- 5381
  for (byte in as.integer(raw)) {
    h <- (h * 33 + byte) %% 2147483647
  }
  sprintf("%08x", as.integer(h))
}

#' Validate a pipeline target declaration.
#'
#' @param target Target spec or ready target.
#' @keywords internal
#' @noRd
.wf_pipeline_target_spec <- function(target) {
  if (inherits(target, "wf_target")) {
    target <- list(mode = "object", target = target)
  }
  if (!is.list(target)) {
    wf_abort("`target` must be a list or wf_target object.", "wf_error_input")
  }
  mode <- target$mode
  if (!.wf_is_string(mode)) {
    wf_abort("`target$mode` must be one non-empty string.", "wf_error_input")
  }
  supported <- c("population", "reference", "manual", "object")
  if (!mode %in% supported) {
    wf_abort(
      sprintf(
        "Unsupported pipeline target mode '%s'. Supported modes: %s.",
        mode,
        paste(supported, collapse = ", ")
      ),
      "wf_error_input",
      list(mode = mode)
    )
  }
  if (mode == "population") {
    if (is.null(target$key_map) || is.null(target$count)) {
      wf_abort(
        "Pipeline target mode 'population' requires `key_map` and `count`.",
        "wf_error_schema"
      )
    }
  }
  if (mode == "reference" && is.null(target$feature)) {
    wf_abort(
      "Pipeline target mode 'reference' requires `feature`.",
      "wf_error_schema"
    )
  }
  if (mode == "object" && !inherits(target$target, "wf_target")) {
    wf_abort(
      "Pipeline target mode 'object' requires `target` to be a wf_target.",
      "wf_error_schema"
    )
  }
  target
}

#' Supported calibration controls by method.
#'
#' @param method Calibration method.
#' @keywords internal
#' @noRd
.wf_pipeline_calibrate_controls <- function(method) {
  common <- c("method", "id")
  switch(
    method,
    raking = c(
      common, "na", "trim", "trim_cycles", "tol", "max_iter",
      "precheck", "init_weight"
    ),
    poststrat = c(
      common, "min_cell", "ladder", "init_weight", "granularity",
      "empty_cell", "precheck", "tol"
    ),
    greg = c(
      common, "bounds", "init_weight", "na", "tol", "max_iter",
      "precheck"
    ),
    logit = c(
      common, "bounds", "init_weight", "na", "tol", "max_iter",
      "precheck"
    ),
    soft = c(
      common, "tolerance", "init_weight", "na", "max_outer", "precheck"
    ),
    ebal = c(
      common, "init_weight", "na", "tol", "max_iter",
      "precheck"
    )
  )
}

#' Validate a pipeline stage declaration.
#'
#' @param stages Named stage list.
#' @keywords internal
#' @noRd
.wf_pipeline_stage_spec <- function(stages) {
  if (!is.list(stages) || is.null(names(stages)) ||
      any(!nzchar(names(stages)))) {
    wf_abort("`stages` must be a named list.", "wf_error_input")
  }
  allowed <- c("propensity", "calibrate")
  unknown <- setdiff(names(stages), allowed)
  if (length(unknown) > 0) {
    wf_abort(
      sprintf(
        "Unknown pipeline stage(s): %s. Supported stages: %s.",
        paste(unknown, collapse = ", "),
        paste(allowed, collapse = ", ")
      ),
      "wf_error_input",
      list(stages = unknown)
    )
  }
  if (is.null(stages$calibrate)) {
    wf_abort(
      "Pipeline stages must include a `calibrate` stage.",
      "wf_error_schema"
    )
  }
  for (stage in names(stages)) {
    if (!is.list(stages[[stage]])) {
      wf_abort(
        sprintf("Pipeline stage '%s' must be a list.", stage),
        "wf_error_input",
        list(stage = stage)
      )
    }
  }

  if (!is.null(stages$propensity)) {
    allowed_propensity <- c(
      "formula", "method", "by", "id", "weight", "stabilize", "trim"
    )
    unknown <- setdiff(names(stages$propensity), allowed_propensity)
    if (length(unknown) > 0) {
      wf_abort(
        sprintf(
          "Unsupported propensity-stage argument(s): %s.",
          paste(unknown, collapse = ", ")
        ),
        "wf_error_input",
        list(arguments = unknown)
      )
    }
    if (is.null(stages$propensity$formula)) {
      wf_abort(
        "Pipeline stage 'propensity' requires `formula`.",
        "wf_error_schema"
      )
    }
  }
  if ("moments" %in% names(stages$calibrate)) {
    .wf_safety_abort(
      "inline_moments_unsupported",
      paste(
        "WFC 2.0 does not accept inline target moments.",
        "Use verified external margins."
      ),
      "moments",
      next_actions = "import_verified_external_margins"
    )
  }

  method <- stages$calibrate$method
  if (is.null(method)) {
    method <- "raking"
  }
  supported <- c("raking", "poststrat", "greg", "logit", "soft", "ebal")
  if (!.wf_is_string(method) || !method %in% supported) {
    shown <- if (length(method) == 0) "<empty>" else as.character(method[[1]])
    wf_abort(
      sprintf(
        "Unsupported pipeline calibration method '%s'. Supported methods: %s.",
        shown,
        paste(supported, collapse = ", ")
      ),
      "wf_error_input",
      list(method = method)
    )
  }
  unknown <- setdiff(
    names(stages$calibrate),
    .wf_pipeline_calibrate_controls(method)
  )
  if (length(unknown) > 0) {
    wf_abort(
      sprintf(
        "Unsupported %s calibration-stage argument(s): %s.",
        method,
        paste(unknown, collapse = ", ")
      ),
      "wf_error_input",
      list(arguments = unknown, method = method)
    )
  }
  stages
}

#' Validate pipeline validation rules.
#'
#' @param validate Validation rule list.
#' @keywords internal
#' @noRd
.wf_pipeline_validation_spec <- function(validate) {
  if (is.null(validate)) {
    return(NULL)
  }
  if (!is.list(validate) || is.null(names(validate)) ||
      any(!nzchar(names(validate)))) {
    wf_abort("`validate` must be NULL or a named list.", "wf_error_input")
  }
  allowed <- c("max_deff", "max_margin_dev")
  unknown <- setdiff(names(validate), allowed)
  if (length(unknown) > 0) {
    wf_abort(
      sprintf(
        "Unsupported validation rule(s): %s.",
        paste(unknown, collapse = ", ")
      ),
      "wf_error_input",
      list(rules = unknown)
    )
  }
  for (rule in names(validate)) {
    value <- validate[[rule]]
    if (length(value) != 1 || !is.numeric(value) ||
        !is.finite(value) || value < 0) {
      wf_abort(
        sprintf("Validation rule `%s` must be one non-negative number.", rule),
        "wf_error_input",
        list(rule = rule, value = value)
      )
    }
  }
  validate
}

#' Declare a production weighting pipeline
#'
#' Creates a serializable specification for a recurring weighting run. The
#' specification records how to build the target, which weighting stages to run,
#' and which post-run validation thresholds to check. It stores no runtime
#' sample data unless the caller deliberately supplies a ready `wf_target`.
#'
#' @param target Target declaration. Use a list with `mode = "population"`,
#'   `"reference"`, or `"manual"`, or pass a ready `wf_target`.
#' @param stages Named stage list. A `calibrate` stage is required; an optional
#'   `propensity` stage runs before calibration.
#' @param validate Optional validation thresholds. Supported keys are
#'   `max_deff` and `max_margin_dev`.
#'
#' @return A `wf_pipeline` object.
#' @export
#'
#' @examples
#' spec <- wf_pipeline(
#'   target = list(
#'     mode = "population",
#'     key_map = c(gender = "gender"),
#'     count = "count"
#'   ),
#'   stages = list(calibrate = list(method = "raking", id = "id")),
#'   validate = list(max_deff = 6)
#' )
wf_pipeline <- function(target, stages, validate = NULL) {
  target <- .wf_pipeline_target_spec(target)
  if (identical(target$mode, "manual")) {
    .wf_warn_deprecated(
      paste(
        "Manual pipeline targets are deprecated because subjective margins",
        "can steer results; use verified external target import instead."
      ),
      feature = "wf_pipeline(target = list(mode = 'manual'))",
      replacement = "wf_guided_plan() with a verified target file",
      risk_code = "subjective_manual_pipeline_target"
    )
  }
  stages <- .wf_pipeline_stage_spec(stages)
  validate <- .wf_pipeline_validation_spec(validate)
  hash_input <- list(target = target, stages = stages, validate = validate)

  structure(
    list(
      target = target,
      stages = stages,
      validate = validate,
      hash = .wf_object_hash(hash_input),
      created = .wf_iso_time(),
      package_version = .wf_package_version()
    ),
    class = "wf_pipeline"
  )
}

#' Print a pipeline specification
#'
#' @param x A `wf_pipeline` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_pipeline <- function(x, ...) {
  cat(sprintf(
    "<wf_pipeline> target: %s; stages: %s; hash: %s\n",
    x$target$mode,
    paste(names(x$stages), collapse = " -> "),
    x$hash
  ))
  if (!is.null(x$validate)) {
    rules <- paste(names(x$validate), unlist(x$validate), sep = "=", collapse = ", ")
    cat(sprintf("  validation: %s\n", rules))
  }
  invisible(x)
}

#' Require a dimensions object for target construction.
#'
#' @param dims Candidate dimensions object.
#' @keywords internal
#' @noRd
.wf_pipeline_require_dims <- function(dims) {
  if (!inherits(dims, "wf_dims")) {
    wf_abort(
      "`dims` must be a wf_dims object when the pipeline builds a target.",
      "wf_error_input"
    )
  }
  invisible(TRUE)
}

#' Build the runtime target for a pipeline run.
#'
#' @param spec A `wf_pipeline` object.
#' @param sample Runtime sample data.
#' @param dims A `wf_dims` object.
#' @param population Runtime population data.
#' @param reference Runtime reference data.
#' @param margins Runtime manual margins.
#' @param need_joint Whether a joint population target is needed.
#' @keywords internal
#' @noRd
.wf_pipeline_build_target <- function(spec, sample, dims, population,
                                      reference, margins, need_joint) {
  target <- spec$target
  mode <- target$mode
  if (mode == "object") {
    return(target$target)
  }

  .wf_pipeline_require_dims(dims)
  args <- target[setdiff(names(target), "mode")]

  if (mode == "population") {
    if (is.null(population)) {
      wf_abort(
        "Pipeline target mode 'population' requires `population` in wf_run().",
        "wf_error_input"
      )
    }
    reserved <- intersect(names(args), c("pop", "dims", "sample"))
    if (length(reserved) > 0) {
      wf_abort(
        sprintf(
          "Pipeline target mode 'population' owns runtime argument(s): %s.",
          paste(reserved, collapse = ", ")
        ),
        "wf_error_schema",
        list(arguments = reserved)
      )
    }
    if (isTRUE(need_joint) && is.null(args$keep_joint)) {
      args$keep_joint <- TRUE
    }
    if (identical(args$scale, "sample")) {
      args$sample <- sample
    }
    return(do.call(
      wf_target_population,
      c(list(pop = population, dims = dims), args)
    ))
  }

  if (mode == "reference") {
    if (is.null(reference)) {
      wf_abort(
        "Pipeline target mode 'reference' requires `reference` in wf_run().",
        "wf_error_input"
      )
    }
    reserved <- intersect(names(args), c("ref", "dims"))
    if (length(reserved) > 0) {
      wf_abort(
        sprintf(
          "Pipeline target mode 'reference' owns runtime argument(s): %s.",
          paste(reserved, collapse = ", ")
        ),
        "wf_error_schema",
        list(arguments = reserved)
      )
    }
    return(do.call(
      wf_target_reference,
      c(list(ref = reference, dims = dims), args)
    ))
  }

  if (mode == "manual") {
    manual_margins <- args$margins
    args$margins <- NULL
    if (is.null(manual_margins)) {
      manual_margins <- margins
    }
    if (is.null(manual_margins)) {
      wf_abort(
        "Pipeline target mode 'manual' requires margins in the spec or wf_run().",
        "wf_error_input"
      )
    }
    reserved <- intersect(names(args), "dims")
    if (length(reserved) > 0) {
      wf_abort(
        "Pipeline target mode 'manual' owns runtime argument `dims`.",
        "wf_error_schema",
        list(arguments = reserved)
      )
    }
    return(do.call(
      wf_target_manual,
      c(list(margins = manual_margins, dims = dims), args)
    ))
  }

  wf_abort("Unsupported pipeline target mode.", "wf_error_internal")
}

#' Choose a collision-free internal column name.
#'
#' @param data Data frame.
#' @param stem Preferred column name.
#' @keywords internal
#' @noRd
.wf_pipeline_internal_col <- function(data, stem) {
  out <- stem
  i <- 1L
  while (out %in% names(data)) {
    i <- i + 1L
    out <- paste0(stem, "_", i)
  }
  out
}

#' Prepare a runtime base-weight column.
#'
#' @param sample Sample data.
#' @param base_weight Column name, numeric vector, or `NULL`.
#' @keywords internal
#' @noRd
.wf_pipeline_base_weight <- function(sample, base_weight) {
  if (is.null(base_weight)) {
    return(list(sample = sample, column = NULL))
  }
  if (.wf_is_string(base_weight)) {
    .require_cols(sample, base_weight, "sample")
    value <- as.numeric(sample[[base_weight]])
    if (anyNA(value) || any(!is.finite(value)) || any(value <= 0)) {
      wf_abort(
        "`base_weight` column must contain finite positive values.",
        "wf_error_input",
        list(base_weight = base_weight)
      )
    }
    return(list(sample = sample, column = base_weight))
  }
  if (is.numeric(base_weight) && length(base_weight) == nrow(sample)) {
    if (anyNA(base_weight) || any(!is.finite(base_weight)) ||
        any(base_weight <= 0)) {
      wf_abort(
        "`base_weight` vector must contain finite positive values.",
        "wf_error_input"
      )
    }
    column <- .wf_pipeline_internal_col(sample, ".wf_base_weight")
    sample[[column]] <- as.numeric(base_weight)
    return(list(sample = sample, column = column))
  }
  wf_abort(
    "`base_weight` must be NULL, a sample column name, or a numeric vector with one value per sample row.",
    "wf_error_input"
  )
}

#' Run an optional propensity stage.
#'
#' @param sample Runtime sample data.
#' @param reference Runtime reference data.
#' @param propensity Propensity stage spec.
#' @param init_col Current initial weight column.
#' @keywords internal
#' @noRd
.wf_pipeline_run_propensity <- function(sample, reference, propensity,
                                        init_col) {
  if (is.null(reference)) {
    wf_abort(
      "Pipeline stage 'propensity' requires `reference` in wf_run().",
      "wf_error_input"
    )
  }

  target_args <- propensity[
    intersect(names(propensity), c("method", "by", "id"))
  ]
  target <- do.call(
    wf_target_propensity,
    c(
      list(
        online = sample,
        reference = reference,
        formula = propensity$formula
      ),
      target_args
    )
  )
  fit_args <- propensity[
    setdiff(names(propensity), c("formula", "method", "by", "id"))
  ]
  stage <- do.call(wf_propensity, c(list(target = target), fit_args))

  sample_ids <- if (is.null(propensity$id)) {
    as.character(seq_len(nrow(sample)))
  } else {
    .chr(sample[[propensity$id]])
  }
  order <- .wf_match_unit_ids(
    data.frame(.wf_id = sample_ids, stringsAsFactors = FALSE),
    ".wf_id",
    stage$data$id,
    "`propensity$data$id`",
    "wf_run() propensity stage"
  )
  stage_col <- .wf_pipeline_internal_col(sample, ".wf_propensity_weight")
  sample[[stage_col]] <- stage$data$weight[order]

  init_out <- stage_col
  if (!is.null(init_col)) {
    combined_col <- .wf_pipeline_internal_col(sample, ".wf_pipeline_init")
    sample[[combined_col]] <- sample[[init_col]] * sample[[stage_col]]
    init_out <- combined_col
  }

  list(sample = sample, column = init_out, result = stage)
}

#' Validate a pipeline result against declared thresholds.
#'
#' @param w Weights.
#' @param target Target.
#' @param rules Validation rules.
#' @keywords internal
#' @noRd
.wf_pipeline_validate_result <- function(w, target, rules) {
  if (is.null(rules)) {
    return(NULL)
  }
  table <- wf_diagnose(w, target = target)$table
  issues <- list()
  if (!is.null(rules$max_deff)) {
    hit <- is.finite(table$deff) & table$deff > rules$max_deff
    if (any(hit)) {
      issues[[length(issues) + 1L]] <- data.frame(
        check = "max_deff",
        group = table$group[hit],
        value = table$deff[hit],
        threshold = rules$max_deff,
        detail = sprintf(
          "Design effect exceeds declared maximum %.6g.",
          rules$max_deff
        ),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!is.null(rules$max_margin_dev) &&
      "margin_maxerr" %in% names(table)) {
    hit <- is.finite(table$margin_maxerr) &
      table$margin_maxerr > rules$max_margin_dev
    if (any(hit)) {
      issues[[length(issues) + 1L]] <- data.frame(
        check = "max_margin_dev",
        group = table$group[hit],
        value = table$margin_maxerr[hit],
        threshold = rules$max_margin_dev,
        detail = sprintf(
          "Margin deviation exceeds declared maximum %.6g.",
          rules$max_margin_dev
        ),
        stringsAsFactors = FALSE
      )
    }
  }
  issues <- if (length(issues) > 0) {
    do.call(rbind, issues)
  } else {
    data.frame(
      check = character(0),
      group = character(0),
      value = numeric(0),
      threshold = numeric(0),
      detail = character(0),
      stringsAsFactors = FALSE
    )
  }
  out <- structure(
    list(
      ok = nrow(issues) == 0,
      issues = issues,
      table = table,
      rules = rules
    ),
    class = "wf_pipeline_validation"
  )
  if (!out$ok) {
    wf_warn(
      sprintf(
        "Pipeline validation detected %d issue(s).",
        nrow(issues)
      ),
      "wf_warning_quality",
      list(issues = issues)
    )
  }
  out
}

#' Run a production weighting pipeline
#'
#' Executes a `wf_pipeline()` specification against runtime sample and target
#' data. The run builds the declared target, optionally fits a propensity
#' pseudo-weight stage, runs the calibration stage, records pipeline provenance,
#' and evaluates any declared validation thresholds.
#'
#' @param spec A `wf_pipeline` object.
#' @param sample Runtime sample data frame.
#' @param dims A `wf_dims` object required when the pipeline builds its target.
#' @param population Runtime population data for `target$mode = "population"`.
#' @param reference Runtime reference data for reference targets or propensity.
#' @param margins Runtime manual margins for `target$mode = "manual"` when
#'   margins are not embedded in the spec.
#' @param base_weight Optional starting weight column or numeric vector. Numeric
#'   vectors make `wf_run()` convenient as a `wf_replicates()` refit body.
#'
#' @return A `wf_weights` object with pipeline provenance and optional
#'   `$pipeline_validation`.
#' @export
wf_run <- function(spec, sample, dims = NULL, population = NULL,
                   reference = NULL, margins = NULL, base_weight = NULL) {
  if (!inherits(spec, "wf_pipeline")) {
    wf_abort("`spec` must be a wf_pipeline object.", "wf_error_input")
  }
  if (!is.data.frame(sample) || nrow(sample) == 0) {
    wf_abort("`sample` must be a non-empty data frame.", "wf_error_input")
  }
  if (!is.null(margins)) {
    .wf_warn_deprecated(
      paste(
        "Runtime manual margins are deprecated because run-time target choices",
        "can steer results; import and review a verified target first."
      ),
      feature = "wf_run(..., margins =)",
      replacement = "wf_guided_plan() with a verified target file",
      risk_code = "subjective_runtime_margins"
    )
  }

  calibrate <- spec$stages$calibrate
  method <- calibrate$method
  if (is.null(method)) {
    method <- "raking"
  }

  base <- .wf_pipeline_base_weight(sample, base_weight)
  work <- base$sample
  init_col <- base$column
  stage_results <- list()

  if (!is.null(spec$stages$propensity)) {
    propensity <- .wf_pipeline_run_propensity(
      work,
      reference,
      spec$stages$propensity,
      init_col
    )
    work <- propensity$sample
    init_col <- propensity$column
    stage_results$propensity <- propensity$result
  }

  target <- .wf_pipeline_build_target(
    spec,
    work,
    dims,
    population,
    reference,
    margins,
    need_joint = identical(method, "poststrat")
  )

  args <- calibrate[setdiff(names(calibrate), "method")]
  if (!is.null(init_col) && !is.null(args$init_weight)) {
    wf_abort(
      "The pipeline has an initial-weight stage and `calibrate$init_weight`; keep only one source of initial weights.",
      "wf_error_input"
    )
  }
  if (!is.null(init_col)) {
    args$init_weight <- init_col
  }
  w <- do.call(
    wf_calibrate,
    c(list(sample = work, target = target, method = method), args)
  )

  w$provenance$pipeline_hash <- spec$hash
  w$provenance$pipeline <- list(
    hash = spec$hash,
    created = spec$created,
    target_mode = spec$target$mode,
    stages = names(spec$stages),
    validate = spec$validate,
    package_version = spec$package_version
  )
  if (length(stage_results) > 0) {
    w$provenance$pipeline_stages <- lapply(stage_results, function(stage) {
      stage$provenance
    })
  }
  validation <- .wf_pipeline_validate_result(w, target, spec$validate)
  if (!is.null(validation)) {
    w$pipeline_validation <- validation
  }
  w
}

#' Compute group-level weight statistics for validation.
#'
#' @param w A `wf_weights` object.
#' @param target Optional target for margin residuals.
#' @keywords internal
#' @noRd
.wf_validation_group_stats <- function(w, target = NULL) {
  if (!is.data.frame(w$data) ||
      !all(c("group", "weight") %in% names(w$data))) {
    wf_abort("`wf_weights` object has malformed `$data`.", "wf_error_internal")
  }
  parts <- split(w$data, w$data$group)
  out <- lapply(parts, function(part) {
    weight <- as.numeric(part$weight)
    total <- sum(weight)
    sum_squares <- sum(weight^2)
    ess <- if (sum_squares > 0) total^2 / sum_squares else NA_real_
    deff <- if (length(weight) > 1 && mean(weight) > 0) {
      1 + (stats::sd(weight) / mean(weight))^2
    } else {
      NA_real_
    }
    data.frame(
      group = part$group[[1]],
      n = nrow(part),
      total_weight = total,
      ess = ess,
      deff = deff,
      stringsAsFactors = FALSE
    )
  })
  stats <- do.call(rbind, out)
  row.names(stats) <- NULL

  if (!is.null(target) && !is.null(w$achieved)) {
    margin <- vapply(stats$group, function(group) {
      if (is.null(target$groups[[group]]) || is.null(w$achieved[[group]])) {
        return(NA_real_)
      }
      max_error <- 0
      for (dim in target$dims) {
        target_margin <- target$groups[[group]]$margins[[dim]]
        current <- w$achieved[[group]][[dim]][names(target_margin)]
        if (is.null(current) || anyNA(current)) {
          return(NA_real_)
        }
        max_error <- max(
          max_error,
          max(abs(current - target_margin) / target_margin)
        )
      }
      max_error
    }, numeric(1))
    stats$margin_maxerr <- margin
  }
  stats
}

#' Validate one drift threshold.
#'
#' @param value Candidate threshold.
#' @param name Threshold name.
#' @param lower Minimum accepted value.
#' @keywords internal
#' @noRd
.wf_validate_threshold <- function(value, name, lower = 0) {
  if (length(value) != 1 || !is.numeric(value) ||
      !is.finite(value) || value < lower) {
    wf_abort(
      sprintf("`%s` must be one finite number >= %g.", name, lower),
      "wf_error_input",
      list(name = name, value = value)
    )
  }
  invisible(TRUE)
}

#' Compare calibrated weights against a reference release
#'
#' Detects drift in recurring production weights by comparing group coverage,
#' design effect, effective sample size, total weight, optional margin
#' residuals, and per-unit weight ratios for matching IDs.
#'
#' @param new New `wf_weights` object.
#' @param reference Reference `wf_weights` object.
#' @param target Optional `wf_target` used to compare margin residual drift.
#' @param max_deff_delta Maximum allowed increase in design effect.
#' @param max_ess_loss Maximum allowed fractional ESS loss.
#' @param max_total_shift Maximum allowed fractional group-total shift.
#' @param max_margin_delta Maximum allowed absolute margin-residual increase.
#' @param max_ratio_p99 Maximum allowed normalized 99th percentile unit-weight
#'   ratio; the reciprocal threshold is applied to the 1st percentile.
#' @param on_issue Reaction when drift is detected: `"warn"`, `"error"`, or
#'   `"none"`.
#'
#' @return A `wf_validation` object.
#' @export
wf_validate <- function(new, reference, target = NULL,
                        max_deff_delta = 1,
                        max_ess_loss = 0.2,
                        max_total_shift = 0.05,
                        max_margin_delta = 0.01,
                        max_ratio_p99 = 2,
                        on_issue = c("warn", "error", "none")) {
  if (!inherits(new, "wf_weights") || !inherits(reference, "wf_weights")) {
    wf_abort(
      "`new` and `reference` must both be wf_weights objects.",
      "wf_error_input"
    )
  }
  if (!is.null(target) && !inherits(target, "wf_target")) {
    wf_abort("`target` must be NULL or a wf_target object.", "wf_error_input")
  }
  on_issue <- match.arg(on_issue)
  .wf_validate_threshold(max_deff_delta, "max_deff_delta")
  .wf_validate_threshold(max_ess_loss, "max_ess_loss")
  .wf_validate_threshold(max_total_shift, "max_total_shift")
  .wf_validate_threshold(max_margin_delta, "max_margin_delta")
  .wf_validate_threshold(max_ratio_p99, "max_ratio_p99", lower = 1)

  new_stats <- .wf_validation_group_stats(new, target)
  ref_stats <- .wf_validation_group_stats(reference, target)
  comparison <- merge(
    new_stats,
    ref_stats,
    by = "group",
    all = TRUE,
    suffixes = c("_new", "_reference")
  )
  comparison$deff_delta <- comparison$deff_new - comparison$deff_reference
  comparison$ess_loss <- ifelse(
    is.finite(comparison$ess_reference) & comparison$ess_reference > 0,
    pmax(0, comparison$ess_reference - comparison$ess_new) /
      comparison$ess_reference,
    NA_real_
  )
  comparison$total_shift <- ifelse(
    is.finite(comparison$total_weight_reference) &
      comparison$total_weight_reference > 0,
    abs(comparison$total_weight_new - comparison$total_weight_reference) /
      comparison$total_weight_reference,
    NA_real_
  )
  if (all(c("margin_maxerr_new", "margin_maxerr_reference") %in%
      names(comparison))) {
    comparison$margin_delta <-
      comparison$margin_maxerr_new - comparison$margin_maxerr_reference
  }

  issue_rows <- list()
  add_issue <- function(check, group, severity, value, threshold, detail) {
    issue_rows[[length(issue_rows) + 1L]] <<- data.frame(
      check = check,
      group = group,
      severity = severity,
      value = value,
      threshold = threshold,
      detail = detail,
      stringsAsFactors = FALSE
    )
  }

  missing_new <- comparison$group[is.na(comparison$n_new)]
  for (group in missing_new) {
    add_issue(
      "group_missing",
      group,
      "error",
      NA_real_,
      NA_real_,
      "Reference group is absent from the new weights."
    )
  }
  missing_ref <- comparison$group[is.na(comparison$n_reference)]
  for (group in missing_ref) {
    add_issue(
      "group_new",
      group,
      "warning",
      NA_real_,
      NA_real_,
      "New group is absent from the reference weights."
    )
  }

  hit <- is.finite(comparison$deff_delta) &
    comparison$deff_delta > max_deff_delta
  for (i in which(hit)) {
    add_issue(
      "deff_delta",
      comparison$group[[i]],
      "warning",
      comparison$deff_delta[[i]],
      max_deff_delta,
      "Design effect increased beyond the declared threshold."
    )
  }
  hit <- is.finite(comparison$ess_loss) &
    comparison$ess_loss > max_ess_loss
  for (i in which(hit)) {
    add_issue(
      "ess_loss",
      comparison$group[[i]],
      "warning",
      comparison$ess_loss[[i]],
      max_ess_loss,
      "Effective sample size fell beyond the declared threshold."
    )
  }
  hit <- is.finite(comparison$total_shift) &
    comparison$total_shift > max_total_shift
  for (i in which(hit)) {
    add_issue(
      "total_shift",
      comparison$group[[i]],
      "warning",
      comparison$total_shift[[i]],
      max_total_shift,
      "Group total weight shifted beyond the declared threshold."
    )
  }
  if ("margin_delta" %in% names(comparison)) {
    hit <- is.finite(comparison$margin_delta) &
      comparison$margin_delta > max_margin_delta
    for (i in which(hit)) {
      add_issue(
        "margin_delta",
        comparison$group[[i]],
        "warning",
        comparison$margin_delta[[i]],
        max_margin_delta,
        "Margin residual increased beyond the declared threshold."
      )
    }
  }

  ratio <- data.frame(
    n_common = integer(0),
    p01 = numeric(0),
    median = numeric(0),
    p99 = numeric(0),
    stringsAsFactors = FALSE
  )
  if (!all(c("id", "weight") %in% names(new$data)) ||
      !all(c("id", "weight") %in% names(reference$data))) {
    wf_abort(
      "Both weight objects must contain `id` and `weight` columns for validation.",
      "wf_error_schema"
    )
  }
  new_ids <- .chr(new$data$id)
  ref_ids <- .chr(reference$data$id)
  if (anyDuplicated(new_ids) || anyDuplicated(ref_ids)) {
    wf_abort(
      "Weight validation requires unique unit IDs in both weight objects.",
      "wf_error_schema"
    )
  }
  common_ids <- intersect(new_ids, ref_ids)
  if (length(common_ids) > 0) {
    unit_ratio <- new$data$weight[match(common_ids, new_ids)] /
      reference$data$weight[match(common_ids, ref_ids)]
    unit_ratio <- unit_ratio[is.finite(unit_ratio) & unit_ratio > 0]
    if (length(unit_ratio) > 0) {
      med <- stats::median(unit_ratio)
      if (is.finite(med) && med > 0) {
        unit_ratio <- unit_ratio / med
      }
      q <- stats::quantile(
        unit_ratio,
        c(0.01, 0.5, 0.99),
        names = FALSE,
        type = 7
      )
      ratio <- data.frame(
        n_common = length(unit_ratio),
        p01 = q[[1]],
        median = q[[2]],
        p99 = q[[3]],
        stringsAsFactors = FALSE
      )
      if (q[[3]] > max_ratio_p99 || q[[1]] < 1 / max_ratio_p99) {
        add_issue(
          "unit_weight_ratio",
          "*",
          "warning",
          max(q[[3]], 1 / q[[1]]),
          max_ratio_p99,
          "Per-unit normalized weight ratios drifted beyond the declared threshold."
        )
      }
    }
  }

  issues <- if (length(issue_rows) > 0) {
    do.call(rbind, issue_rows)
  } else {
    data.frame(
      check = character(0),
      group = character(0),
      severity = character(0),
      value = numeric(0),
      threshold = numeric(0),
      detail = character(0),
      stringsAsFactors = FALSE
    )
  }
  out <- structure(
    list(
      ok = nrow(issues) == 0,
      issues = issues,
      comparison = comparison,
      ratio = ratio,
      thresholds = list(
        max_deff_delta = max_deff_delta,
        max_ess_loss = max_ess_loss,
        max_total_shift = max_total_shift,
        max_margin_delta = max_margin_delta,
        max_ratio_p99 = max_ratio_p99
      )
    ),
    class = "wf_validation"
  )
  if (!out$ok && on_issue == "warn") {
    wf_warn(
      sprintf("Weight validation detected %d drift issue(s).", nrow(issues)),
      "wf_warning_quality",
      list(issues = issues)
    )
  }
  if (!out$ok && on_issue == "error") {
    wf_abort(
      sprintf("Weight validation detected %d drift issue(s).", nrow(issues)),
      "wf_error_input",
      list(issues = issues)
    )
  }
  out
}

#' Print a weight-validation result
#'
#' @param x A `wf_validation` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_validation <- function(x, ...) {
  cat(sprintf(
    "<wf_validation> %s\n",
    if (x$ok) "PASS" else "DRIFT DETECTED"
  ))
  if (nrow(x$issues) > 0) {
    show <- utils::head(x$issues, 12)
    for (i in seq_len(nrow(show))) {
      cat(sprintf(
        "  [%s] %s / %s: %s\n",
        show$severity[[i]],
        show$check[[i]],
        show$group[[i]],
        show$detail[[i]]
      ))
    }
    if (nrow(x$issues) > nrow(show)) {
      cat(sprintf("  ... and %d more issue(s)\n", nrow(x$issues) - nrow(show)))
    }
  }
  invisible(x)
}

#' Escape one string for JSON.
#'
#' @param x Character scalar.
#' @keywords internal
#' @noRd
.wf_json_escape <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  x
}

#' Serialize simple R objects to JSON.
#'
#' @param x Object to serialize.
#' @keywords internal
#' @noRd
.wf_json <- function(x) {
  scalar <- function(value) {
    if (is.na(value)) {
      return("null")
    }
    if (is.logical(value)) {
      return(if (isTRUE(value)) "true" else "false")
    }
    if (is.numeric(value)) {
      if (!is.finite(value)) {
        return(paste0("\"", as.character(value), "\""))
      }
      return(format(value, digits = 15, scientific = FALSE, trim = TRUE))
    }
    paste0("\"", .wf_json_escape(as.character(value)), "\"")
  }

  if (is.null(x)) {
    return("null")
  }
  if (inherits(x, "formula")) {
    return(.wf_json(paste(deparse(x), collapse = " ")))
  }
  if (inherits(x, "POSIXt")) {
    return(.wf_json(.wf_iso_time(x)))
  }
  if (is.call(x) || is.name(x)) {
    return(.wf_json(paste(deparse(x), collapse = " ")))
  }
  if (is.environment(x)) {
    return("\"<environment>\"")
  }
  if (is.function(x)) {
    return("\"<function>\"")
  }
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (is.data.frame(x)) {
    rows <- lapply(seq_len(nrow(x)), function(i) {
      as.list(x[i, , drop = FALSE])
    })
    return(paste0("[", paste(vapply(rows, .wf_json, ""), collapse = ","), "]"))
  }
  if (is.list(x)) {
    names_x <- names(x)
    if (!is.null(names_x) && all(nzchar(names_x))) {
      values <- vapply(seq_along(x), function(i) {
        paste0("\"", .wf_json_escape(names_x[[i]]), "\":", .wf_json(x[[i]]))
      }, "")
      return(paste0("{", paste(values, collapse = ","), "}"))
    }
    return(paste0("[", paste(vapply(x, .wf_json, ""), collapse = ","), "]"))
  }
  if (length(x) == 0) {
    return("[]")
  }
  names_x <- names(x)
  if (!is.null(names_x) && all(nzchar(names_x))) {
    values <- vapply(seq_along(x), function(i) {
      paste0("\"", .wf_json_escape(names_x[[i]]), "\":", scalar(x[[i]]))
    }, "")
    return(paste0("{", paste(values, collapse = ","), "}"))
  }
  if (length(x) == 1) {
    return(scalar(x))
  }
  paste0("[", paste(vapply(x, scalar, ""), collapse = ","), "]")
}

#' Create an audit payload.
#'
#' @param x Result object.
#' @param inputs Optional named input list.
#' @param extra Optional metadata.
#' @keywords internal
#' @noRd
.wf_audit_payload <- function(x, inputs = NULL, extra = NULL) {
  ledger <- NULL
  diagnostics <- NULL
  object_class <- class(x)
  weights <- NULL
  if (inherits(x, "wf_autoweigh_result")) {
    ledger <- x$ledger
    diagnostics <- x$diagnostics
    weights <- x$weights
  } else if (inherits(x, "wf_weights")) {
    weights <- x
  }

  identities <- list(
    design = NULL,
    target = NULL,
    cell_plan = NULL,
    plan = NULL,
    approval = NULL,
    locked_weight = NULL,
    source = NULL,
    source_data = NULL,
    impact = NULL
  )
  if (inherits(x, "wf_safe_workflow")) {
    if (!identical(x$identity, .wf_safe_workflow_identity(x))) {
      .wf_safety_abort(
        "safe_workflow_invalid",
        "The safe workflow changed after its identity was recorded.",
        "x"
      )
    }
    identities$design <- x$design$identity
    identities$target <- x$target$identity
    identities$cell_plan <- x$cell_plan$identity
    identities$plan <- x$plan$identity
    identities$source <- x$target$evidence$source_checksum
    identities$source_data <- x$target$evidence$data_checksum
  } else if (inherits(x, "wf_locked_weights")) {
    if (!identical(x$identity, .wf_locked_weight_identity(x))) {
      .wf_safety_abort(
        "locked_weights_invalid",
        "The locked weights changed after their identity was recorded.",
        "x"
      )
    }
    identities$design <- x$design_identity
    identities$target <- x$target_identity
    identities$cell_plan <- x$provenance$safety$cell_plan_identity
    identities$plan <- x$plan_identity
    identities$approval <- x$approval_identity
    identities$locked_weight <- x$identity
    identities$source <- x$provenance$safety$source_metadata_checksum
    identities$source_data <- x$provenance$safety$source_data_checksum
  } else if (inherits(x, "wf_impact")) {
    if (!identical(x$identity, .wf_impact_identity(x))) {
      .wf_safety_abort(
        "impact_identity_invalid",
        "The impact result changed after its identity was recorded.",
        "x"
      )
    }
    identities$locked_weight <- x$weight_identity
    identities$impact <- x$identity
  } else if (inherits(x, "wf_plan_approval")) {
    if (!identical(x$identity, .wf_plan_approval_identity(x))) {
      .wf_safety_abort(
        "plan_approval_invalid",
        "The approval changed after its identity was recorded.",
        "x"
      )
    }
    identities$plan <- x$plan_identity
    identities$approval <- x$identity
  } else if (inherits(x, "wf_weight_plan")) {
    if (!identical(x$identity, .wf_weight_plan_identity(x))) {
      .wf_safety_abort(
        "weight_plan_invalid",
        "The weight plan changed after its identity was recorded.",
        "x"
      )
    }
    identities$design <- x$input_identities$design
    identities$target <- x$input_identities$target
    identities$cell_plan <- x$input_identities$cell_plan
    identities$plan <- x$identity
  } else if (inherits(x, "wf_cell_merge_plan")) {
    if (!identical(x$identity, .wf_cell_plan_identity(x))) {
      .wf_safety_abort(
        "cell_plan_invalid",
        "The cell plan changed after its identity was recorded.",
        "x"
      )
    }
    identities$design <- x$input_identities$design
    identities$target <- x$input_identities$target
    identities$cell_plan <- x$identity
  } else if (inherits(x, "wf_verified_target")) {
    if (!identical(x$identity, .wf_verified_target_identity(x))) {
      .wf_safety_abort(
        "target_identity_invalid",
        "The verified target changed after its identity was recorded.",
        "x"
      )
    }
    identities$target <- x$identity
    identities$source <- x$evidence$source_checksum
    identities$source_data <- x$evidence$data_checksum
  } else if (inherits(x, "wf_design_data")) {
    if (!identical(x$identity, .wf_design_identity(x$data, x$roles))) {
      .wf_safety_abort(
        "design_identity_invalid",
        "The design data changed after their identity was recorded.",
        "x"
      )
    }
    identities$design <- x$identity
  }
  identity_names <- c(
    "design", "target", "cell_plan", "plan", "approval",
    "locked_weight", "source", "source_data", "impact"
  )
  for (name in setdiff(identity_names, names(identities))) {
    identities[name] <- list(NULL)
  }
  identities <- identities[identity_names]

  input_hashes <- NULL
  if (!is.null(inputs)) {
    if (!is.list(inputs) || is.null(names(inputs)) ||
        any(!nzchar(names(inputs)))) {
      wf_abort("`inputs` must be NULL or a named list.", "wf_error_input")
    }
    input_hashes <- vapply(inputs, .wf_object_hash, character(1))
  }

  n_units <- if (!is.null(weights) && is.data.frame(weights$data)) {
    nrow(weights$data)
  } else if (inherits(x, "wf_safe_workflow")) {
    nrow(x$design$data)
  } else if (inherits(x, "wf_design_data")) {
    nrow(x$data)
  } else {
    NULL
  }
  groups <- if (!is.null(weights) && is.data.frame(weights$data) &&
      "group" %in% names(weights$data)) {
    unique(.chr(weights$data$group))
  } else if (inherits(x, "wf_safe_workflow")) {
    names(x$target$groups)
  } else if (inherits(x, "wf_verified_target")) {
    names(x$groups)
  } else {
    NULL
  }
  weight_summary <- if (!is.null(weights) && is.data.frame(weights$data) &&
      "weight" %in% names(weights$data)) {
    list(
      total = sum(weights$data$weight),
      min = min(weights$data$weight),
      max = max(weights$data$weight),
      mean = mean(weights$data$weight)
    )
  } else {
    NULL
  }
  provenance <- if (!is.null(weights)) {
    weights$provenance
  } else if (inherits(x, "wf_safe_workflow")) {
    list(
      workflow_identity = x$identity,
      method = x$plan$method,
      package_version = x$package_version
    )
  } else if (!is.null(x$provenance)) {
    x$provenance
  } else {
    NULL
  }

  list(
    schema = "wfc_audit_v2",
    exported = .wf_iso_time(),
    package = list(name = "WFC", version = .wf_package_version()),
    object_class = object_class,
    n_units = n_units,
    groups = groups,
    weight_summary = weight_summary,
    provenance = provenance,
    decision_ledger = ledger,
    diagnostics = diagnostics,
    input_hashes = input_hashes,
    identities = identities,
    extra = extra
  )
}

#' Export a self-contained WFC audit file
#'
#' Writes a JSON audit record containing result provenance, pipeline metadata,
#' optional guided-workflow decision ledger, input hashes, and user-supplied
#' extra metadata. The writer is dependency-free and intended for machine
#' archiving, not human formatting.
#'
#' @param x A WFC result, safe workflow, plan, approval, locked weights, verified
#'   target, design-data object, or post-lock impact object.
#' @param file Output JSON file path.
#' @param inputs Optional named list of input objects whose hashes should be
#'   recorded.
#' @param extra Optional additional metadata to include in the audit record.
#'
#' @return Invisibly returns `file`.
#' @export
wf_audit_export <- function(x, file, inputs = NULL, extra = NULL) {
  supported <- c(
    "wf_weights", "wf_autoweigh_result", "wf_safe_workflow",
    "wf_weight_plan", "wf_cell_merge_plan", "wf_plan_approval",
    "wf_verified_target", "wf_design_data", "wf_impact"
  )
  if (!inherits(x, supported)) {
    wf_abort(
      "`x` must be a supported WFC result or safe-workflow evidence object.",
      "wf_error_input"
    )
  }
  if (!.wf_is_string(file)) {
    wf_abort("`file` must be one non-empty path.", "wf_error_input")
  }
  directory <- dirname(file)
  if (!dir.exists(directory)) {
    wf_abort(
      sprintf("Output directory does not exist: %s", directory),
      "wf_error_input",
      list(directory = directory)
    )
  }
  payload <- .wf_audit_payload(x, inputs = inputs, extra = extra)
  writeLines(.wf_json(payload), file, useBytes = TRUE)
  invisible(file)
}
