# Migrating from WFC 1.x to WFC 2.0

WFC 2.0 makes the verified, outcome-blind workflow mandatory. The practical
change is simple: data used to choose weights must be separated from study
outcomes, and weighting targets must come from identifiable external evidence.

## What changes

| WFC 1.x use | WFC 2.0 action | Reason |
| --- | --- | --- |
| Raw sample passed to a calibration function | Prepare `wf_design_data` first | Prevents outcomes from entering weight construction |
| Ordinary or hand-built `wf_target` | Import a `wf_verified_target` with source evidence | Makes the origin and unchanged content checkable |
| `wf_target_manual()` | No supported replacement | A user-selected target can steer the result |
| `wf_target_shrink()` | No supported replacement | A chosen blend coefficient can steer the result |
| `wf_calibrate(..., moments = ...)` | No supported replacement for inline moments | Desired means may encode a preferred outcome |
| Manual pipeline mode | Use a verified target object | Removes unreviewed target creation at run time |
| `wf_run(..., margins = ...)` | Import, plan, approve, then execute | Run-time margins bypass source review |
| Pass-rate or desired outcome interval from a predecessor package | No supported replacement | Outcome targets are not legitimate weighting inputs |

The absence of a replacement is intentional. Do not reproduce a removed
behavior by relabeling an outcome, generating a target after viewing results, or
editing an imported object.

## Import example for a survey researcher

Suppose `survey-design.csv` contains only `person_id`, `age_group`, `region`,
and an optional base weight. It must not contain the study outcomes used later.
Suppose `population-margins.csv` is the machine-readable table and
`population-source.pdf` is the independently obtained source document.

```r
library(WFC)

dims <- wf_dims(
  age_group = c("18-34", "35-54", "55+"),
  region = c("north", "south")
)

design <- wf_prepare_design(
  data = read.csv("survey-design.csv"),
  id = "person_id",
  calibration = c("age_group", "region"),
  base_weight = "base_weight"
)

target <- wf_import_target(
  data_file = "population-margins.csv",
  source_file = "population-source.pdf",
  dims = dims,
  key_map = c(age_group = "age_group", region = "region"),
  count = "population_count",
  production = TRUE
)

cell_plan <- wf_plan_cells(design, target, dims)
plan <- wf_plan_weights(
  design,
  target,
  dims,
  method = "raking",
  cell_plan = cell_plan
)

approval <- wf_approve_plan(
  plan,
  approver = "Qualified reviewer full name",
  role = "Statistician",
  note = "Reviewed source, support, limits, and intended analysis"
)

weights <- wf_execute_plan(plan, approval, design, target)
decision_view <- wf_report(weights, target, audience = "decision")
statistical_view <- wf_report(weights, target, audience = "statistician")
```

Use `wf_target_template("population-margins-template.csv", dims)` if the expected
table layout is unknown. The template is a formatting aid, not source evidence.

## Import example for an AI agent

An agent should construct the same objects and stop before human approval. It
must preserve returned identities instead of recreating or editing objects.

```r
request <- list(
  design_file = "survey-design.csv",
  target_file = "population-margins.csv",
  source_file = "population-source.pdf",
  id = "person_id",
  calibration = c("age_group", "region")
)

design <- wf_prepare_design(
  read.csv(request$design_file),
  id = request$id,
  calibration = request$calibration,
  base_weight = "base_weight"
)

target <- wf_import_target(
  request$target_file,
  request$source_file,
  dims = dims,
  key_map = c(age_group = "age_group", region = "region"),
  count = "population_count",
  production = TRUE
)

plan <- wf_plan_weights(design, target, dims, method = "raking")

handoff <- list(
  plan = plan,
  plan_identity = plan$identity,
  design_identity = design$identity,
  target_identity = target$identity,
  required_human_action = "Review and approve the unchanged plan"
)
```

After a qualified human returns a `wf_plan_approval`, the agent may call
`wf_execute_plan()` with the original unchanged design, target, and plan. An
agent must not set `actor_type = "human"` for itself or fabricate a person's
name.

## Reference-target import

When the legitimate target is a probability-like feature from an independent
reference sample, use the separate reference importer:

```r
target <- wf_import_reference(
  data_file = "reference-sample.csv",
  source_file = "reference-methodology.pdf",
  dims = dims,
  feature = "reference_weight",
  production = TRUE
)
```

This path is not permission to use a study outcome as the feature. The reference
sample and its role must be independently justified and reviewed.

## Existing scripts

Migrate in this order:

1. Identify and remove outcomes from the weighting input table.
2. Record the external target table and its source-evidence file.
3. Import the target and retain its identity.
4. Create a deterministic cell plan and weight plan.
5. Obtain qualified, accountable human approval of the unchanged plan.
6. Execute once, lock weights, and attach them to the full analysis data.
7. Produce decision and statistical views from the same result object.
8. Export the audit record used for review.

Scripts that depend on removed behavior need a scientific redesign, not an API
rename. WFC 2.0 provides no compatibility switch for those behaviors.
