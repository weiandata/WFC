# WFC 1.0 API Freeze

This document records the public WFC core API frozen at version 1.0.0.
It is installed with the package so downstream tools, WFCstudio, and release
reviewers can inspect the compatibility contract without reading development
design documents.

## Compatibility Policy

From 1.0.0 onward, WFC follows these rules:

- Additive changes are allowed in minor releases: new exported functions, new
  optional arguments with backward-compatible defaults, new S3 methods, new
  columns, and new list fields.
- Removals, renamed exported functions, required new arguments, changed default
  behavior, changed class inheritance, or changed meanings of existing
  programmatic fields require a major version.
- Deprecated APIs must warn with class `wf_warning_deprecated` for at least one
  full minor release before removal.
- Human-facing wording may change, including localized labels and report prose.
  English object names, condition classes, ledger keys, and table column names
  are the stable programmatic interface.
- Optional ecosystem integrations remain optional. Missing suggested packages
  must continue to fail with classed WFC dependency errors rather than becoming
  hard dependencies.

## Frozen Exported Signatures

```r
as_svrepdesign(r, data, id = "id", degf = NULL, ...)
as_svydesign(w, data, id = "id", ids = ~1, strata = NULL, fpc = NULL,
             nest = FALSE, ...)
wf_apply_collapse(sample, target, plan)
wf_attrition(panel, retained, formula, id = NULL, by = NULL,
             stabilize = TRUE, trim = NULL)
wf_audit_export(x, file, inputs = NULL, extra = NULL)
wf_auto_trim(sample, target, id = NULL,
             caps = c(2, 3, 4, 5, 6, 8, 10, 12),
             lo = 0.05, max_deff = 6, max_residual = 0.02, ...)
wf_autoweigh(sample, population, dims, key_map = NULL, count = NULL,
             by = NULL, id = NULL,
             method = c("auto", "raking", "poststrat", "logit"),
             ladder = NULL, min_cell = NULL, bounds = c(0.3, 3),
             trim = "auto", max_deff = 6, max_residual = 0.02,
             interactive = base::interactive(), lang = NULL, ...)
wf_blend(online, offline, by_cell,
         lambda = c("neff", "inverse_variance", "fixed"),
         lambda_fixed = NULL, outcome = NULL,
         level = c("cell", "group"), trim_lambda = c(0.05, 0.95),
         sensitivity = TRUE)
wf_calibrate(sample, target, method = "raking", ...)
wf_collapse_ladder(dims, ...)
wf_compose(..., id = NULL, normalize = c("none", "mean1", "sum"))
wf_diagnose(w, target = NULL, sample = NULL, deff_ok = 3,
            deff_caveat = 10)
wf_dims(..., .collapse = list())
wf_influence(w, target = NULL, sample = NULL, id = NULL, top = 20)
wf_pipeline(target, stages, validate = NULL)
wf_plan_poststrat(sample, target, min_cell, ladder,
                  granularity = c("adaptive", "province"),
                  empty_cell = c("redistribute", "flag", "error"),
                  id = NULL)
wf_poststrat(sample, target, min_cell, ladder, init_weight = NULL,
             granularity = c("adaptive", "province"),
             empty_cell = c("redistribute", "flag", "error"),
             id = NULL, precheck = TRUE, tol = 1e-8,
             parallel = FALSE, progress = FALSE)
wf_precheck(sample, target, id = NULL,
            na = c("fractional", "drop", "error"),
            max_na_dims = 2, thin_min = 5, risk_ratio = 10)
wf_propensity(target, weight = c("ipw", "kernel", "matching"),
              stabilize = TRUE, trim = NULL)
wf_rake(sample, target, id = NULL,
        na = c("fractional", "drop", "error"),
        trim = NULL, trim_cycles = 4, tol = 1e-6, max_iter = 200,
        precheck = TRUE, init_weight = NULL,
        parallel = FALSE, progress = FALSE)
wf_replicates(data, refit,
              method = c("bootstrap", "jackknife", "brr"),
              R = 500, strata = NULL, clusters = NULL, id = NULL,
              base_weight = NULL, seed = NULL, rho = 0,
              parallel = FALSE, progress = FALSE)
wf_report(w, target = NULL, audience = c("manager", "analyst"),
          lang = NULL, output = c("object", "markdown", "html"),
          file = NULL)
wf_run(spec, sample, dims = NULL, population = NULL, reference = NULL,
       margins = NULL, base_weight = NULL)
wf_suggest_collapse(precheck, dims,
                    checks = c("cat_infeasible", "support_thin",
                               "risk_extreme_ratio"),
                    max_steps = 1)
wf_suggest_ladder(sample, target, dims, min_cell = 5)
wf_target_manual(margins, dims, dim_col = "dimension",
                 cat_col = "category", value_col = "value", by = NULL,
                 group_col = by, totals = NULL, mode = "manual")
wf_target_population(pop, key_map, count, dims, by = NULL, by_key = NULL,
                     scale = c("population", "sample", "custom"),
                     sample = NULL, totals = NULL, keep_joint = FALSE)
wf_target_propensity(online, reference, formula,
                     method = c("logit", "rf", "gbm"),
                     by = NULL, id = NULL)
wf_target_reference(ref, feature, dims, by = NULL,
                    feature_na = c("error", "drop"),
                    feature_gt1 = c("warn", "allow"))
wf_target_shrink(target, reference, lambda, groups = NULL)
wf_validate(new, reference, target = NULL, max_deff_delta = 1,
            max_ess_loss = 0.2, max_total_shift = 0.05,
            max_margin_delta = 0.01, max_ratio_p99 = 2,
            on_issue = c("warn", "error", "none"))
wf_variance(replicates, estimator, data, level = 0.95,
            ci = c("normal", "percentile"))
```

## Stable Object Contracts

The following fields are stable when present on their corresponding objects:

- `wf_target`: `mode`, `by`, `dims`, `groups`, `meta`, `joint`.
- `wf_weights`: `data`, `log`, `achieved`, `provenance`; `data` includes at
  least `id`, `group`, `weight`, and `feature`.
- `wf_replicate_weights`: `base`, `replicates`, `scale`, `rscales`, `method`,
  `rho`, `design`, and `provenance`.
- `wf_diagnostics`: `table` with English programmatic column names.
- `wf_quality_report`: `summary`, `sections`, `audience`, `language`, and
  structured section tables.
- `wf_autoweigh_result`: `weights`, `diagnostics`, `report`, `target`,
  `final_sample`, `ledger`, `method`, and `language`.
- `wf_pipeline`: `target`, `stages`, `validate`, `created`, and `hash`.
- `wf_validation`: `ok`, `issues`, `comparison`, `ratio`, and `thresholds`.

Additive fields may appear in these objects. Existing fields must not be
renamed, removed, or repurposed without a major version.

## Stable Condition Classes

The public classed-condition taxonomy is:

- Errors: `wf_error`, `wf_error_input`, `wf_error_schema`,
  `wf_error_feasibility`, `wf_error_convergence`, `wf_error_design`,
  `wf_error_dependency`, and `wf_error_internal`.
- Warnings: `wf_warning`, `wf_warning_data`, `wf_warning_quality`, and
  `wf_warning_deprecated`.

Condition messages are human-facing and may be improved. Condition classes and
machine-readable `data` payload names are the stable programmatic surface.

## WFCstudio Boundary

WFCstudio beta targets WFC `>= 1.0.0, < 2.0.0`. It may call exported WFC APIs
and render WFC objects, but it must not implement statistical engines, suppress
blocking WFC conditions, rename stable keys, or add hard dependencies to WFC.
The detailed sibling-package contract is in `inst/design/wfcstudio_contract.md`.

## WFC 1.1 Additive Safety API

WFC 1.1 adds the following exported interfaces without changing the frozen 1.0
numeric contracts:

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
```

`wf_report()` additionally accepts `audience = "decision"` as an alias for
`"manager"` and `audience = "statistician"` as an alias for `"analyst"`. Audit
exports use `wfc_audit_v2`, preserving the v1 fields and adding nullable safety
identity fields.

The new safety objects add stable SHA-256 `identity` fields. Safety errors use
class `wf_error_safety` and a machine payload with `code`, `severity`, `field`,
`evidence`, and `next_actions`.

The following 1.0 interfaces remain numerically compatible in 1.1 but warn with
`wf_warning_deprecated` on every use and are scheduled for removal in 2.0.0:

- manual target margins;
- target shrinkage;
- inline entropy-balancing moment targets;
- manual pipeline target declarations and runtime margin injection.

Their warning payload adds `removal` and `risk_code` to the frozen `feature` and
`replacement` fields. The verified workflow has no bypass, self-approval,
automatic limit widening, automatic relaxation, or silent method-switch path.
