# WFC 2.0 Safety Contract

This installed contract defines the supported weighting boundary for WFC 2.0.
It replaces the WFC 1.x compatibility surface where that surface allowed a
user-selected target to reach a weighting engine. The WFC 1.0 freeze remains an
historical record; this document is authoritative for WFC 2.0.

## Required boundary

A supported weighting run starts with both of these objects:

- a `wf_design_data` created by `wf_prepare_design()`, containing only unit
  identity, declared calibration variables, and declared design variables; and
- a non-demo `wf_verified_target` created by `wf_import_target()` or
  `wf_import_reference()` from unchanged external data and source-evidence
  files.

Planning is deterministic and outcome-blind. A human approves the immutable
plan before execution. Changing the design, target, plan, or approval invalidates
the chain. An AI agent may prepare and inspect artifacts but cannot approve its
own plan.

## Retained safe exports

The supported end-to-end signatures are:

```r
wf_prepare_design(data, id, calibration, base_weight = NULL,
                  strata = NULL, clusters = NULL, fpc = NULL)
wf_target_template(file, dims, by = NULL, example = FALSE)
wf_import_target(data_file, source_file, dims, key_map, count,
                 by = NULL, by_key = NULL, production = TRUE)
wf_import_reference(data_file, source_file, dims, feature,
                    by = NULL, production = TRUE)
wf_plan_cells(design, target, dims, min_cell = 5,
              max_weight_ratio = 4, boundary = target$by, ladder = NULL)
wf_plan_weights(design, target, dims,
                method = c("raking", "logit", "poststrat"),
                bounds = c(0.3, 3), min_cell = 5, cell_plan = NULL)
wf_approve_plan(plan, approver, role, note = NULL, actor_type = "human")
wf_execute_plan(plan, approval, design, target)
wf_guided_plan(data, id, calibration, dims, target_file, source_file,
               source_type = c("population", "reference"), key_map = NULL,
               count = NULL, feature = NULL, ...)
wf_guided_execute(workflow, approval)
wf_attach_weights(data, weights, id, weight_name = ".weight")
wf_assess_impact(weights, data, id, outcomes, level = 0.95)
wf_report(w, target = NULL,
          audience = c("manager", "analyst", "decision", "statistician"),
          lang = NULL, output = c("object", "markdown", "html"), file = NULL)
wf_audit_export(x, file, inputs = NULL, extra = NULL)
```

Direct public calibration functions remain available for statistical users and
agents that already hold safe objects. Their first two inputs are a
`wf_design_data` and a `wf_verified_target`; raw data frames and ordinary
`wf_target` objects are rejected before engine execution:

```r
wf_calibrate(design, target, method = "raking", ...)
wf_rake(design, target, ...)
wf_poststrat(design, target, min_cell, ladder, ...)
wf_auto_trim(design, target,
             caps = c(2, 3, 4, 5, 6, 8, 10, 12),
             lo = 0.05, max_deff = 6, max_residual = 0.02, ...)
wf_autoweigh(design, target, dims,
             method = c("auto", "raking", "poststrat", "logit"), ...)
wf_pipeline(target, stages, validate = NULL)
wf_run(spec, sample, dims = NULL, population = NULL,
       reference = NULL, base_weight = NULL)
```

Categorical entropy calibration is retained only when its constraints come
from the supplied verified external target. It cannot accept inline moments.
Other reporting, diagnostics, replicate-weight, variance, and interoperability
exports remain available, but none may create or replace a weighting target.

## Removed interfaces

The following interfaces are absent in WFC 2.0:

- `wf_target_manual()`;
- `wf_target_shrink()`;
- the `moments` argument accepted through `wf_calibrate(..., moments = ...)`;
- `wf_pipeline(target = list(mode = "manual"), ...)`;
- the `margins` argument of `wf_run()`; and
- any path that sends a raw sample or an unverified target directly to a
  weighting engine.

There is no legacy shim, environment switch, warning-only fallback, unsafe
override, automatic approval, or silent method change.

## No supported replacement

There is no supported replacement for pass-rate targets, desired outcome
means, desired outcome intervals, outcome-heterogeneity objectives, subjective
manual targets, target shrinkage, inline outcome moments, or target-driven
relaxation. These behaviors are intentionally not migrated from predecessor
packages because they can steer results toward a preferred conclusion.

A verified population or reference margin is a replacement only when it is a
genuine, independently sourced design target. Relabeling an outcome goal as a
margin does not make it supported.

## Stable safety object fields

Additive fields may be introduced, but these fields retain their meaning:

- `wf_design_data`: `data`, `roles`, `identity`, `created`, and
  `package_version`;
- `wf_verified_target`: the inherited `wf_target` fields `mode`, `by`, `dims`,
  `groups`, `meta`, and `joint`, plus `evidence`, `demo_only`, `source_type`,
  and `identity`;
- `wf_cell_merge_plan`: `cells_before`, `cells_after`, `map`, `category_maps`,
  `reasons`, `affected_share`, `unresolved_cells`,
  `projected_max_weight_ratio`, `input_identities`, `settings`, `created`,
  `package_version`, and `identity`;
- `wf_weight_plan`: `method`, `settings`, `precheck`, `issues`, `ready`,
  `cell_plan`, `input_identities`, `effective_identities`, `weights`, `created`,
  `package_version`, and `identity`;
- `wf_plan_approval`: `plan_identity`, `approver`, `role`, `note`,
  `actor_type`, `attestation`, `created`, `package_version`, and `identity`;
- `wf_weights`: `data`, `log`, `achieved`, and `provenance`, with immutable
  safety identities recorded in `provenance`; and
- `wf_impact`: `summary`, `weight_identity`, `outcomes`, `level`, `created`,
  `package_version`, and `identity`.

SHA-256 identity values are stable machine-readable links between artifacts.
They are not proof that the source evidence is truthful.

## Stable safety conditions

Safety refusals inherit from `wf_error_safety` and `wf_error`. Their payload
contains `code`, `severity`, `field`, `evidence`, and `next_actions`. Existing
codes keep their meanings. Important WFC 2.0 codes include:

- `verified_target_required`, `demo_target_in_production`, and
  `target_identity_invalid`;
- `design_identity_invalid`, `weight_plan_invalid`, and
  `plan_approval_mismatch`;
- `human_approval_required` and `verified_weighting_inputs_required`;
- `inline_moments_unsupported`, `design_role_override_unsupported`, and
  `manual_pipeline_unsupported`; and
- `target_design_roles_mismatch` and `pipeline_target_type_mismatch`.

Human-facing wording may improve. Code, class, severity, field, evidence, and
next-action keys are the programmatic contract for agents.

## Reporting contract

`audience = "decision"` or `"manager"` gives a short plain-language status,
principal risks, and next actions. `audience = "statistician"` or `"analyst"`
gives the full structured diagnostics and provenance needed for further work.
Both views are projections of the same result object and must reconcile.

Package-level review or release approval never authorizes a particular public
or client analysis. Each consequential analysis needs its own accountable and
qualified human review.
