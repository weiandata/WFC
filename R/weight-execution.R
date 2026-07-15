#' Calculate the identity of a plan approval.
#'
#' @param approval Approval fields.
#' @keywords internal
#' @noRd
.wf_plan_approval_identity <- function(approval) {
  .wf_sha256_object(approval[setdiff(names(approval), "identity")])
}

#' Execute one weighting engine behind the verified-input boundary.
#'
#' @param design An unchanged `wf_design_data`.
#' @param target An unchanged, non-demo `wf_verified_target`.
#' @param method Internal engine identifier.
#' @param settings Named engine settings.
#' @keywords internal
#' @noRd
.wf_execute_verified_engine <- function(design, target, method, settings = list()) {
  design_ok <- inherits(design, "wf_design_data") &&
    identical(design$identity, .wf_design_identity(design$data, design$roles))
  target_ok <- inherits(target, "wf_verified_target") &&
    !isTRUE(target$demo_only) &&
    identical(target$identity, .wf_verified_target_identity(target))
  if (!design_ok || !target_ok) {
    .wf_safety_abort(
      "verified_weighting_inputs_required",
      paste(
        "Weighting requires an unchanged wf_design_data and a non-demo",
        "wf_verified_target."
      ),
      "design,target",
      next_actions = c("prepare_design_data", "import_verified_target")
    )
  }
  required_columns <- unique(c(target$by, target$dims))
  allowed_columns <- unique(c(
    design$roles$calibration,
    design$roles$strata,
    design$roles$clusters,
    design$roles$fpc
  ))
  missing_roles <- setdiff(required_columns, allowed_columns)
  if (length(missing_roles) > 0L) {
    .wf_safety_abort(
      "target_design_roles_mismatch",
      "Target fields must be declared design or calibration variables.",
      "target",
      evidence = list(columns = missing_roles),
      next_actions = "prepare_matching_design_data"
    )
  }
  settings_named <- is.list(settings) &&
    (length(settings) == 0L ||
     (!is.null(names(settings)) && all(nzchar(names(settings)))))
  if (!settings_named) {
    .wf_safety_abort(
      "weighting_settings_invalid",
      "Weighting settings must be a named list.",
      "settings"
    )
  }
  owned <- intersect(names(settings), c("sample", "design", "target", "id", "init_weight"))
  if (length(owned) > 0L) {
    .wf_safety_abort(
      "design_role_override_unsupported",
      "WFC owns sample, target, ID, and base-weight roles after design preparation.",
      owned[[1]],
      evidence = list(arguments = owned),
      next_actions = "prepare_design_with_required_roles"
    )
  }

  base <- list(
    sample = design$data,
    target = target,
    id = design$roles$id,
    init_weight = design$roles$base_weight
  )
  weights <- switch(
    method,
    raking = do.call(.wf_rake_engine, c(base, settings)),
    poststrat = do.call(.wf_poststrat_engine, c(base, settings)),
    greg = do.call(
      .wf_calibrate_engine,
      c(base[c("sample", "target")], list(method = method),
        base[c("id", "init_weight")], settings)
    ),
    logit = do.call(
      .wf_calibrate_engine,
      c(base[c("sample", "target")], list(method = method),
        base[c("id", "init_weight")], settings)
    ),
    soft = do.call(
      .wf_calibrate_engine,
      c(base[c("sample", "target")], list(method = method),
        base[c("id", "init_weight")], settings)
    ),
    ebal = do.call(
      .wf_calibrate_engine,
      c(base[c("sample", "target")], list(method = method),
        base[c("id", "init_weight")], settings)
    ),
    auto_trim = do.call(.wf_auto_trim_engine, c(base, settings)),
    autoweigh = {
      dims <- settings$dims
      settings$dims <- NULL
      do.call(
        .wf_autoweigh_engine,
        c(
          list(
            sample = design$data,
            population = target,
            dims = dims,
            id = design$roles$id
          ),
          if (!is.null(design$roles$base_weight)) {
            c(settings, list(init_weight = design$roles$base_weight))
          } else {
            settings
          }
        )
      )
    },
    .wf_safety_abort(
      "weight_method_unsupported",
      "The requested weighting method is not supported.",
      "method",
      evidence = list(method = method)
    )
  )

  if (inherits(weights, "wf_autoweigh_result")) {
    weights$weights$provenance$design_identity <- design$identity
    weights$weights$provenance$target_identity <- target$identity
    weights$design_identity <- design$identity
    weights$target_identity <- target$identity
  } else if (inherits(weights, "wf_weights")) {
    weights$provenance$design_identity <- design$identity
    weights$provenance$target_identity <- target$identity
  }
  weights
}

#' Record a human attestation for a reviewed weight plan
#'
#' Approval records are separate from plans. AI agents may prepare plans but
#' cannot create an approval while declaring themselves as an agent.
#'
#' @param plan An unchanged, review-ready `wf_weight_plan`.
#' @param approver Non-empty approver name or organizational identifier.
#' @param role Non-empty reviewing role.
#' @param note Optional review note.
#' @param actor_type Actor type. Only `"human"` is accepted.
#'
#' @return A `wf_plan_approval` attestation bound to the plan identity.
#' @export
wf_approve_plan <- function(plan, approver, role, note = NULL,
                            actor_type = "human") {
  if (!inherits(plan, "wf_weight_plan") ||
      !identical(plan$identity, .wf_weight_plan_identity(plan))) {
    .wf_safety_abort(
      "weight_plan_invalid",
      "`plan` must be an unchanged wf_weight_plan object.",
      "plan"
    )
  }
  if (!isTRUE(plan$ready)) {
    .wf_safety_abort(
      "weight_plan_blocked",
      "A plan with blocking precheck issues cannot be approved.",
      "plan",
      evidence = list(issues = plan$issues),
      next_actions = "resolve_precheck_issues"
    )
  }
  if (!identical(actor_type, "human")) {
    .wf_safety_abort(
      "human_approval_required",
      "Only a human reviewer may attest approval of a weight plan.",
      "actor_type",
      next_actions = "request_human_review"
    )
  }
  if (!.wf_is_string(approver) || !nzchar(trimws(approver))) {
    .wf_safety_abort(
      "approver_missing",
      "`approver` must identify the human reviewer.",
      "approver"
    )
  }
  if (!.wf_is_string(role) || !nzchar(trimws(role))) {
    .wf_safety_abort(
      "approver_role_missing",
      "`role` must identify the reviewer's role.",
      "role"
    )
  }
  if (!is.null(note) && (!.wf_is_string(note) || !nzchar(trimws(note)))) {
    .wf_safety_abort(
      "approval_note_invalid",
      "`note` must be NULL or one non-empty string.",
      "note"
    )
  }

  approval <- list(
    plan_identity = plan$identity,
    approver = trimws(approver),
    role = trimws(role),
    note = note,
    actor_type = actor_type,
    attestation = paste(
      "I reviewed the plan inputs, source evidence, checks, method,",
      "bounds, and any stored category merges."
    ),
    created = .wf_iso_time(),
    package_version = .wf_package_version()
  )
  approval$identity <- .wf_plan_approval_identity(approval)
  class(approval) <- "wf_plan_approval"
  approval
}

#' Calculate the immutable identity of locked weights.
#'
#' @param weights Locked-weight fields.
#' @keywords internal
#' @noRd
.wf_locked_weight_identity <- function(weights) {
  .wf_sha256_object(list(
    data = weights$data,
    plan_identity = weights$plan_identity,
    approval_identity = weights$approval_identity,
    design_identity = weights$design_identity,
    target_identity = weights$target_identity,
    effective_design_identity = weights$effective_design_identity,
    effective_target_identity = weights$effective_target_identity,
    method = weights$provenance$method
  ))
}

#' Execute an approved plan and lock its weights
#'
#' Revalidates the plan, human approval, design data, target evidence, and any
#' stored cell map before calling exactly the method recorded in the plan.
#'
#' @param plan An unchanged `wf_weight_plan`.
#' @param approval A matching `wf_plan_approval`.
#' @param design The unchanged `wf_design_data` used to build the plan.
#' @param target The unchanged `wf_verified_target` used to build the plan.
#'
#' @return A `wf_locked_weights` object that also inherits from `wf_weights`.
#' @export
wf_execute_plan <- function(plan, approval, design, target) {
  if (!inherits(plan, "wf_weight_plan") ||
      !identical(plan$identity, .wf_weight_plan_identity(plan)) ||
      !isTRUE(plan$ready)) {
    .wf_safety_abort(
      "weight_plan_not_executable",
      "The weight plan is changed or has blocking issues.",
      "plan"
    )
  }
  if (!inherits(approval, "wf_plan_approval") ||
      !identical(approval$identity, .wf_plan_approval_identity(approval)) ||
      !identical(approval$actor_type, "human") ||
      !identical(approval$plan_identity, plan$identity)) {
    .wf_safety_abort(
      "plan_approval_mismatch",
      "A current human approval matching this exact plan is required.",
      "approval",
      next_actions = "request_human_review"
    )
  }
  if (!inherits(design, "wf_design_data") ||
      !identical(design$identity, .wf_design_identity(design$data, design$roles)) ||
      !identical(design$identity, plan$input_identities$design)) {
    .wf_safety_abort(
      "execution_design_mismatch",
      "Design data do not match the approved plan.",
      "design"
    )
  }
  if (!inherits(target, "wf_verified_target") || isTRUE(target$demo_only) ||
      !identical(target$identity, .wf_verified_target_identity(target)) ||
      !identical(target$identity, plan$input_identities$target)) {
    .wf_safety_abort(
      "execution_target_mismatch",
      "The verified target does not match the approved plan.",
      "target"
    )
  }

  effective_design <- design
  effective_target <- target
  if (!is.null(plan$cell_plan)) {
    applied <- .wf_apply_cell_plan(design, target, plan$cell_plan)
    effective_design <- applied$design
    effective_target <- applied$target
  }
  if (!identical(effective_design$identity, plan$effective_identities$design) ||
      !identical(effective_target$identity, plan$effective_identities$target)) {
    .wf_safety_abort(
      "execution_effective_inputs_mismatch",
      "Effective inputs no longer match the reviewed plan.",
      "plan"
    )
  }

  method <- plan$method
  if (identical(method, "raking")) {
    settings <- list(
      trim = plan$settings$bounds,
      precheck = TRUE
    )
  } else if (identical(method, "logit")) {
    settings <- list(
      bounds = plan$settings$bounds,
      precheck = TRUE
    )
  } else if (identical(method, "poststrat")) {
    dim_args <- stats::setNames(
      rep(list(NULL), length(effective_target$dims)),
      effective_target$dims
    )
    effective_dims <- do.call(wf_dims, dim_args)
    identity_ladder <- wf_collapse_ladder(effective_dims)
    settings <- list(
      min_cell = plan$settings$min_cell,
      ladder = identity_ladder,
      empty_cell = "error",
      precheck = TRUE
    )
  } else {
    .wf_safety_abort(
      "approved_method_unsupported",
      "The approved method is not supported by safe execution.",
      "method"
    )
  }
  weights <- .wf_execute_verified_engine(
    effective_design,
    effective_target,
    method,
    settings
  )

  .wf_match_unit_ids(
    effective_design$data,
    effective_design$roles$id,
    weights$data$id,
    "calibrated weights",
    "wf_execute_plan()"
  )
  if (any(!is.finite(weights$data$weight)) || any(weights$data$weight <= 0)) {
    wf_abort(
      "Approved calibration did not produce finite positive weights.",
      "wf_error_feasibility",
      .wf_safety_payload(
        "locked_weights_invalid",
        "blocking",
        "weight",
        list(rows = which(!is.finite(weights$data$weight) |
          weights$data$weight <= 0)),
        "review_calibration_feasibility"
      )
    )
  }

  weights$plan_identity <- plan$identity
  weights$approval_identity <- approval$identity
  weights$design_identity <- design$identity
  weights$target_identity <- target$identity
  weights$effective_design_identity <- effective_design$identity
  weights$effective_target_identity <- effective_target$identity
  weights$locked_at <- .wf_iso_time()
  weights$provenance$safety <- list(
    plan_identity = plan$identity,
    approval_identity = approval$identity,
    approver = approval$approver,
    approver_role = approval$role,
    source_checksum = target$evidence$data_checksum,
    source_data_checksum = target$evidence$data_checksum,
    source_metadata_checksum = target$evidence$source_checksum,
    cell_plan_identity = plan$input_identities$cell_plan
  )
  weights$identity <- .wf_locked_weight_identity(weights)
  class(weights) <- c("wf_locked_weights", "wf_weights")
  weights
}

#' Calculate the identity of a guided safe workflow.
#'
#' @param workflow Workflow fields.
#' @keywords internal
#' @noRd
.wf_safe_workflow_identity <- function(workflow) {
  .wf_sha256_object(list(
    design = workflow$design$identity,
    target = workflow$target$identity,
    cell_plan = workflow$cell_plan$identity,
    plan = workflow$plan$identity
  ))
}

#' Prepare a guided safe weighting workflow
#'
#' This practitioner-oriented entry point composes design preparation, verified
#' target import, outcome-blind cell planning, and weight planning. It never
#' approves a plan or computes weights.
#'
#' @param data Design-only data frame.
#' @param id Unique identifier column.
#' @param calibration Declared calibration and boundary columns.
#' @param dims A `wf_dims` object.
#' @param target_file CSV or XLSX target file.
#' @param source_file Companion source DCF file.
#' @param source_type Either `"population"` or `"reference"`.
#' @param key_map Population dimension-to-column mapping.
#' @param count Population count column.
#' @param feature Reference reciprocal-design-weight column.
#' @param ... Named safe settings: `base_weight`, `strata`, `clusters`, `fpc`,
#'   `by`, `by_key`, `production`, `method`, `bounds`, `min_cell`,
#'   `max_weight_ratio`, `boundary`, and `ladder`.
#'
#' @return A reviewable `wf_safe_workflow`; no weights are computed.
#' @export
wf_guided_plan <- function(data, id, calibration, dims,
                           target_file, source_file,
                           source_type = c("population", "reference"),
                           key_map = NULL, count = NULL, feature = NULL, ...) {
  dots <- list(...)
  allowed <- c(
    "base_weight", "strata", "clusters", "fpc", "by", "by_key",
    "production", "method", "bounds", "min_cell", "max_weight_ratio",
    "boundary", "ladder"
  )
  if (length(dots) && (is.null(names(dots)) || any(!nzchar(names(dots))))) {
    .wf_safety_abort(
      "guided_settings_unnamed",
      "All guided workflow settings must be named.",
      "..."
    )
  }
  unknown <- setdiff(names(dots), allowed)
  if (length(unknown)) {
    .wf_safety_abort(
      "guided_setting_unsupported",
      sprintf("Unsupported guided setting(s): %s.", paste(unknown, collapse = ", ")),
      "...",
      evidence = list(settings = unknown)
    )
  }
  value <- function(name, default = NULL) {
    if (name %in% names(dots)) dots[[name]] else default
  }

  source_type <- match.arg(source_type)
  design <- wf_prepare_design(
    data,
    id = id,
    calibration = calibration,
    base_weight = value("base_weight"),
    strata = value("strata"),
    clusters = value("clusters"),
    fpc = value("fpc")
  )
  if (identical(source_type, "population")) {
    if (is.null(key_map) || is.null(count)) {
      .wf_safety_abort(
        "population_import_mapping_missing",
        "Population targets require `key_map` and `count`.",
        "key_map",
        next_actions = "supply_population_column_mapping"
      )
    }
    target <- wf_import_target(
      target_file,
      source_file,
      dims,
      key_map = key_map,
      count = count,
      by = value("by"),
      by_key = value("by_key"),
      production = value("production", TRUE)
    )
  } else {
    if (is.null(feature)) {
      .wf_safety_abort(
        "reference_feature_missing",
        "Reference targets require `feature`.",
        "feature"
      )
    }
    target <- wf_import_reference(
      target_file,
      source_file,
      dims,
      feature = feature,
      by = value("by"),
      production = value("production", TRUE)
    )
  }

  cell_plan <- wf_plan_cells(
    design,
    target,
    dims,
    min_cell = value("min_cell", 5),
    max_weight_ratio = value("max_weight_ratio", 4),
    boundary = value("boundary", target$by),
    ladder = value("ladder")
  )
  plan <- wf_plan_weights(
    design,
    target,
    dims,
    method = value("method", "raking"),
    bounds = value("bounds", c(0.3, 3)),
    min_cell = value("min_cell", 5),
    cell_plan = cell_plan
  )
  workflow <- list(
    design = design,
    target = target,
    cell_plan = cell_plan,
    plan = plan,
    weights = NULL,
    created = .wf_iso_time(),
    package_version = .wf_package_version()
  )
  workflow$identity <- .wf_safe_workflow_identity(workflow)
  class(workflow) <- "wf_safe_workflow"
  workflow
}

#' Execute a guided workflow with an external human approval
#'
#' @param workflow An unchanged `wf_safe_workflow`.
#' @param approval A matching `wf_plan_approval` created separately.
#'
#' @return A `wf_locked_weights` object.
#' @export
wf_guided_execute <- function(workflow, approval) {
  if (!inherits(workflow, "wf_safe_workflow") ||
      !identical(workflow$identity, .wf_safe_workflow_identity(workflow))) {
    .wf_safety_abort(
      "safe_workflow_invalid",
      "`workflow` must be an unchanged wf_safe_workflow object.",
      "workflow"
    )
  }
  wf_execute_plan(
    workflow$plan,
    approval,
    workflow$design,
    workflow$target
  )
}

#' Attach locked weights to analysis data by exact unit ID
#'
#' @param data Full analysis data frame.
#' @param weights An unchanged `wf_locked_weights` object.
#' @param id Unique identifier column in `data`.
#' @param weight_name Name of the appended weight column.
#'
#' @return `data` in its original row order with one locked-weight column.
#' @export
wf_attach_weights <- function(data, weights, id, weight_name = ".weight") {
  if (!is.data.frame(data)) {
    .wf_safety_abort(
      "analysis_data_invalid",
      "`data` must be a data frame.",
      "data"
    )
  }
  if (!inherits(weights, "wf_locked_weights") ||
      !identical(weights$identity, .wf_locked_weight_identity(weights))) {
    .wf_safety_abort(
      "locked_weights_invalid",
      "`weights` must be unchanged locked weights.",
      "weights"
    )
  }
  if (!.wf_is_string(weight_name) || !nzchar(weight_name)) {
    .wf_safety_abort(
      "weight_name_invalid",
      "`weight_name` must be one non-empty column name.",
      "weight_name"
    )
  }
  if (weight_name %in% names(data)) {
    .wf_safety_abort(
      "weight_column_exists",
      sprintf("Column '%s' already exists.", weight_name),
      "weight_name",
      next_actions = "choose_new_weight_column"
    )
  }

  index <- .wf_match_unit_ids(
    data,
    id,
    weights$data$id,
    "locked weights",
    "wf_attach_weights()"
  )
  data[[weight_name]] <- weights$data$weight[index]
  attr(data, "wf_locked_weight_identity") <- weights$identity
  data
}
