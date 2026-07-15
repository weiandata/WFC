#' Calculate the identity of a weight plan.
#'
#' @param plan Weight-plan fields.
#' @keywords internal
#' @noRd
.wf_weight_plan_identity <- function(plan) {
  material <- plan[setdiff(names(plan), c("created", "identity"))]
  if (!is.null(material$cell_plan)) {
    material$cell_plan <- material$cell_plan$identity
  }
  .wf_sha256_object(material)
}

#' Build a reviewable outcome-blind weight plan
#'
#' Performs structural checks and records approved-capable settings without
#' calling a calibration engine or computing any weights.
#'
#' @param design A `wf_design_data` object.
#' @param target A non-demo `wf_verified_target` object.
#' @param dims A `wf_dims` object matching the target.
#' @param method Planned method: `"raking"`, `"logit"`, or `"poststrat"`.
#' @param bounds Planned multiplicative lower and upper bounds, satisfying
#'   `0 < L < 1 < U`.
#' @param min_cell Minimum support recorded in the plan.
#' @param cell_plan Optional reviewed `wf_cell_merge_plan` to apply before
#'   calibration.
#'
#' @return A `wf_weight_plan`. The `weights` field is always `NULL`.
#' @export
wf_plan_weights <- function(design, target, dims,
                            method = c("raking", "logit", "poststrat"),
                            bounds = c(0.3, 3), min_cell = 5,
                            cell_plan = NULL) {
  if (!inherits(design, "wf_design_data") ||
      !identical(design$identity, .wf_design_identity(design$data, design$roles))) {
    .wf_safety_abort(
      "design_object_invalid",
      "`design` must be an unchanged wf_design_data object.",
      "design"
    )
  }
  if (!inherits(target, "wf_verified_target") || isTRUE(target$demo_only) ||
      !identical(target$identity, .wf_verified_target_identity(target))) {
    .wf_safety_abort(
      "verified_target_required",
      "`target` must be an unchanged, non-demo verified external target.",
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
  if (length(method) < 1L || !is.character(method) ||
      !method[[1]] %in% c("raking", "logit", "poststrat")) {
    .wf_safety_abort(
      "weight_method_unsupported",
      "`method` must be raking, logit, or poststrat.",
      "method"
    )
  }
  method <- match.arg(method)
  if (!is.numeric(bounds) || length(bounds) != 2L || anyNA(bounds) ||
      any(!is.finite(bounds)) ||
      !(bounds[[1]] > 0 && bounds[[1]] < 1 && bounds[[2]] > 1)) {
    .wf_safety_abort(
      "weight_bounds_invalid",
      "`bounds` must satisfy 0 < lower < 1 < upper.",
      "bounds"
    )
  }
  if (!is.numeric(min_cell) || length(min_cell) != 1L ||
      is.na(min_cell) || !is.finite(min_cell) || min_cell < 1 ||
      min_cell != as.integer(min_cell)) {
    .wf_safety_abort(
      "min_cell_invalid",
      "`min_cell` must be a positive integer.",
      "min_cell"
    )
  }
  if (identical(method, "poststrat") && is.null(target$joint)) {
    .wf_safety_abort(
      "poststrat_joint_target_required",
      "Post-stratification requires verified joint population cells.",
      "target",
      next_actions = "import_joint_population_target"
    )
  }

  effective_design <- design
  effective_target <- target
  if (!is.null(cell_plan)) {
    if (!inherits(cell_plan, "wf_cell_merge_plan") ||
        !identical(cell_plan$identity, .wf_cell_plan_identity(cell_plan))) {
      .wf_safety_abort(
        "cell_plan_invalid",
        "`cell_plan` must be an unchanged wf_cell_merge_plan object.",
        "cell_plan"
      )
    }
    if (!identical(cell_plan$input_identities$design, design$identity) ||
        !identical(cell_plan$input_identities$target, target$identity)) {
      .wf_safety_abort(
        "cell_plan_inputs_mismatch",
        "The cell plan does not match the supplied design and target.",
        "cell_plan"
      )
    }
    applied <- .wf_apply_cell_plan(design, target, cell_plan)
    effective_design <- applied$design
    effective_target <- applied$target
  }

  precheck <- wf_precheck(
    effective_design$data,
    effective_target,
    id = effective_design$roles$id,
    thin_min = as.integer(min_cell),
    risk_ratio = max(bounds[[2]], 1 / bounds[[1]])
  )
  plan <- list(
    method = method,
    settings = list(
      bounds = unname(bounds),
      min_cell = as.integer(min_cell),
      dims = names(dims$vars)
    ),
    precheck = precheck,
    issues = precheck$issues,
    ready = isTRUE(precheck$ok),
    cell_plan = cell_plan,
    input_identities = list(
      design = design$identity,
      target = target$identity,
      cell_plan = if (is.null(cell_plan)) NULL else cell_plan$identity
    ),
    effective_identities = list(
      design = effective_design$identity,
      target = effective_target$identity
    ),
    weights = NULL,
    created = .wf_iso_time(),
    package_version = .wf_package_version()
  )
  plan$identity <- .wf_weight_plan_identity(plan)
  class(plan) <- "wf_weight_plan"
  plan
}

#' Print a reviewable weight plan
#'
#' @param x A `wf_weight_plan` object.
#' @param ... Reserved for future use.
#'
#' @return `x`, invisibly.
#' @export
print.wf_weight_plan <- function(x, ...) {
  cat("<wf_weight_plan>\n")
  cat(" Method: ", x$method, "\n", sep = "")
  cat(" Review status: ", if (x$ready) "READY" else "BLOCKED", "\n", sep = "")
  cat(" Issues: ", nrow(x$issues), "\n", sep = "")
  cat(" Weights computed: no\n")
  cat(" Identity: ", x$identity, "\n", sep = "")
  invisible(x)
}
