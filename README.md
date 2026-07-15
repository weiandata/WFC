# WFC

WFC is an R package for reviewable survey weighting. Version 2.0 makes one
rule non-optional: weights may be built only from declared design variables and
an independently sourced, verified target. Study outcomes enter only after the
weights are locked.

This design serves two kinds of users:

- survey researchers get a guided sequence with plain-language stops and next
  actions; and
- statistical teams and AI agents get stable objects, identities, condition
  codes, and complete audit fields.

The same result can be shown as a short decision view or a detailed statistical
view. The two views come from one object and must agree.

## What WFC 2.0 prevents

Public weighting functions reject raw data frames, ordinary target objects,
demo targets, changed identities, self-approval by an agent, and runtime
changes to ID or base-weight roles. Manual targets, target shrinkage, inline
target moments, manual pipeline modes, and runtime margin injection are not
supported.

These controls reduce accidental and ordinary misuse. They cannot prove that a
source document is truthful or stop a determined person from editing open
source code. Accountable human review remains necessary.

## Installation

Install the development version from GitHub:

```r
remotes::install_github("weiandata/WFC")
```

## Files used by the safe workflow

A production run normally starts with four files:

1. a design-only survey table containing IDs, calibration fields, and declared
   sampling-design fields;
2. a separate analysis table containing study outcomes;
3. a CSV or Excel target table from an external authority; and
4. a companion `.source.dcf` evidence record for that target table.

Use `wf_target_template()` if the target-table layout is unfamiliar:

```r
library(WFC)

dims <- wf_dims(
  age_group = c("18-34", "35-54", "55+"),
  region = c("north", "south")
)

wf_target_template(
  "population-margins-template.csv",
  dims = dims
)
```

The template creates the data file and its companion DCF form. Complete the
source fields, update the checksum after the data file is final, and obtain the
file before inspecting study outcomes.

WFC also installs synthetic format examples named `safe-target-example.csv`,
`safe-target-example.xlsx`, and their separate `.source.dcf` files. They are
marked demo-only and cannot enter production planning.

<!-- SAFE_WORKFLOW_START -->

## Complete controlled workflow

### 1. Prepare outcome-free design data

```r
library(WFC)

dims <- wf_dims(
  age_group = c("18-34", "35-54", "55+"),
  region = c("north", "south")
)

design_only <- read.csv("survey-design.csv")
analysis_data <- read.csv("survey-outcomes.csv")

design <- wf_prepare_design(
  design_only,
  id = "person_id",
  calibration = c("age_group", "region"),
  base_weight = "base_weight"
)
```

Every column in `design_only` must have a declared design role. Keep outcomes
such as satisfaction, vote choice, approval, score, or pass/fail in
`analysis_data`.

### 2. Import an external target and its evidence

Population-count target:

```r
target <- wf_import_target(
  data_file = "population-margins.csv",
  source_file = "population-margins.csv.source.dcf",
  dims = dims,
  key_map = c(age_group = "age_group", region = "region"),
  count = "population_count",
  production = TRUE
)
```

Independent reference-sample target:

```r
reference_target <- wf_import_reference(
  data_file = "reference-sample.csv",
  source_file = "reference-sample.csv.source.dcf",
  dims = dims,
  feature = "reference_weight",
  production = TRUE
)
```

Import verifies source completeness, declared selection timing, demo status,
and the SHA-256 checksum. It does not decide whether the source is scientifically
appropriate; that remains part of human review.

### 3. Plan without seeing outcomes

```r
cell_plan <- wf_plan_cells(
  design,
  target,
  dims,
  min_cell = 5,
  max_weight_ratio = 4
)

plan <- wf_plan_weights(
  design,
  target,
  dims,
  method = "raking",
  bounds = c(0.3, 3),
  min_cell = 5,
  cell_plan = cell_plan
)

plan$ready
plan$issues
is.null(plan$weights)
```

Planning does not calculate weights. It records the exact inputs, checks,
method, limits, and any deterministic category merge for review.

### 4. Obtain separate human approval

```r
approval <- wf_approve_plan(
  plan,
  approver = "Qualified reviewer full name",
  role = "Statistician",
  note = "Reviewed source, support, method, limits, and intended use"
)
```

An AI agent may prepare the plan but may not create this attestation for itself.
The name and role must identify the actual human reviewer.

### 5. Execute the unchanged plan once

```r
locked <- wf_execute_plan(
  plan,
  approval,
  design,
  target
)
```

Changing the design, target, plan, or approval breaks the identity chain and
stops execution.

### 6. Attach outcomes after weight locking

```r
analysis_ready <- wf_attach_weights(
  analysis_data,
  locked,
  id = "person_id",
  weight_name = ".weight"
)

impact <- wf_assess_impact(
  locked,
  analysis_data,
  id = "person_id",
  outcomes = c("satisfaction", "approved")
)
```

Impact assessment describes what the already locked weights change. It cannot
re-plan, reapprove, or overwrite the weights.

### 7. Produce views for different readers

```r
decision_view <- wf_report(
  locked,
  audience = "decision"
)

statistical_view <- wf_report(
  locked,
  audience = "statistician"
)

impact_detail <- wf_report(
  impact,
  audience = "statistician"
)

wf_audit_export(locked, "weighting-audit.json")
```

The decision view emphasizes status, main risks, and next actions. The
statistical view exposes full tables, convergence information, identities, and
provenance for further analysis.

<!-- SAFE_WORKFLOW_END -->

## Direct functions for statistical users

Advanced users may call `wf_calibrate()`, `wf_rake()`, `wf_poststrat()`,
`wf_auto_trim()`, or `wf_autoweigh()` directly, but their first inputs must
still be the unchanged `design` and `target` objects:

```r
raked <- wf_rake(design, target, tol = 1e-8)

bounded <- wf_calibrate(
  design,
  target,
  method = "logit",
  bounds = c(0.3, 3)
)

trim_review <- wf_auto_trim(
  design,
  target,
  caps = c(2, 4, 6, 8)
)
```

ID and base-weight columns come from `wf_prepare_design()` and cannot be
overridden at this stage.

## AI agent integration

An agent should preserve whole WFC objects and their identities. A minimal
handoff object can be prepared like this:

```r
handoff <- list(
  plan = plan,
  plan_identity = plan$identity,
  design_identity = design$identity,
  target_identity = target$identity,
  required_human_action = "Review and approve the unchanged plan"
)
```

If an agent attempts approval, WFC returns `wf_error_safety`. Agents should read
the stable payload and stop:

```r
refusal <- tryCatch(
  wf_approve_plan(
    plan,
    approver = "Automated agent",
    role = "assistant",
    actor_type = "agent"
  ),
  wf_error_safety = function(condition) condition$data
)

refusal[c("code", "severity", "field", "next_actions")]
```

Do not edit identities, manufacture a human name, widen limits, switch targets,
or retry after viewing outcomes.

## Migration from WFC 1.x

See [Migrating from WFC 1.x to WFC 2.0](docs/migration/wfc-1-to-2.md). Behavior
that selected desired results has no compatibility switch and no supported
replacement.

## License

WFC is licensed under GPL (>= 2). Copyright and contributor information are in
`inst/COPYRIGHTS` and `DESCRIPTION`.
