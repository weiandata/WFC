# Safe consolidation of mergecalib and ratecalib into WFC

| Field | Value |
|---|---|
| Status | Approved design |
| Date | 2026-07-15 |
| Owner | WEIAN DATA TECH (Beijing) Co., Ltd. |
| Accountable maintainer | Kunxiang Ma |
| Operating mode | Controlled |
| Target releases | WFC 1.1 deprecation bridge and WFC 2.0 enforcement |

## 1. Decision

WFC will absorb only the defensible, outcome-blind capabilities of
`mergecalib` and `ratecalib`. The old packages are algorithm and test references,
not APIs to copy. Capabilities that calibrate weights or select cell merges to
match desired study outcomes will not be migrated.

The supported WFC workflow will enforce this rule:

> Weight construction may use sampling-design variables and independently
> sourced population or reference information. It must not inspect study
> outcomes or choose targets, merge plans, tuning parameters, or weight bounds
> in response to preferred findings.

WFC 1.1 will introduce the safe workflow and deprecate incompatible interfaces.
WFC 2.0 will enforce the new boundary. The two predecessor repositories will be
archived only after WFC 2.0, its migration material, and its validation evidence
are complete.

## 2. Context and risk finding

### 2.1 ratecalib

`ratecalib` is designed to adjust weights toward user-supplied overall and
subgroup pass rates. It also accepts exact constraints, soft priorities,
categorical proportions, means, and totals. This outcome-targeting behavior is
the package's central statistical contract, not an isolated option. A notice or
consent prompt cannot make that contract outcome-blind.

The following experience remains useful: input checking, feasibility
diagnostics, bounded weights, replicate-weight workflows, result diagnostics,
and CSV/Excel handling. These ideas may be reimplemented against WFC's safe
objects. Pass-rate and arbitrary study-result target calibration will not be
migrated.

### 2.2 mergecalib

`mergecalib` combines defensible structural behavior with outcome-dependent
optimization. Defensible behavior includes deterministic within-province
candidate construction, positive-support guarantees, weight-distortion limits,
conservation checks, and auditable merge maps. Unsafe behavior includes
constraining outcome-grade proportions to user-supplied intervals, choosing
plans using outcome heterogeneity, and expanding the merge search to satisfy
those intervals.

WFC may reimplement support-based merging. Planning must depend only on declared
design variables, sample support, initial design weights, adjacency rules, and
independent population information. Outcome counts, rates, grades, scores, and
other analysis variables must not enter planning or optimization.

### 2.3 Existing WFC exposure

WFC 1.0 already exposes interfaces that can accept subjective targets:

- `wf_target_manual()` accepts arbitrary margin tables;
- `wf_target_shrink()` blends targets using a user-selected coefficient;
- `wf_calibrate(method = "ebal", moments = ...)` accepts inline target means;
- pipeline manual-target modes can construct targets without external-source
  evidence.

These interfaces are part of the WFC 1.0 compatibility contract. Changing their
meaning or removing them requires a major release. A safe consolidation
therefore requires both a WFC 1.1 transition and a WFC 2.0 boundary.

## 3. Scope

### 3.1 In scope

- a design-only input object with explicit column roles;
- independent population and reference-source target objects;
- CSV and Excel import with mandatory source metadata and examples;
- outcome-blind sparse-cell and category-collapse planning;
- a separate review and approval step before applying a plan;
- bounded calibration, feasibility checks, diagnostics, conservation checks,
  replicate uncertainty, and audit export;
- a guided interface for social-survey practitioners;
- deterministic structured interfaces for AI agents;
- decision-maker and statistician views over the same result object;
- post-lock comparison of unweighted and weighted study estimates;
- staged deprecation, major-version migration, and predecessor archival.

### 3.2 Out of scope

- targets chosen to create a preferred pass rate, score, mean, total, treatment
  effect, or subgroup finding;
- outcome-grade interval constraints;
- outcome heterogeneity as a merge objective;
- silent target relaxation, method switching, bound widening, or merge-range
  expansion;
- compatibility shims that reproduce prohibited behavior under new names;
- authentication of a human approver inside standalone R;
- prevention of deliberate source-code modification or deliberate relabeling of
  an outcome as a design variable;
- deletion or rewriting of predecessor Git history.

## 4. Users and presentation contracts

### 4.1 Social-survey practitioner

The guided workflow uses a small number of ordered steps: prepare design data,
import independent targets, precheck, plan, review, approve, execute, attach
weights, and report. Conservative defaults are used. Chinese and English
messages explain the problem, why it matters, and permitted next actions.
Users are not required to configure solver penalties or similar numerical
controls.

### 4.2 AI agent

The same statistical engine exposes non-interactive, deterministic objects.
Conditions contain stable codes, severity, affected fields, machine-readable
data, and permitted next actions. Agents can run checks, create plans, and
explain evidence. They cannot use an agent-only bypass, suppress blocking
conditions, or treat their own assertion as accountable approval.

The WFC package records approval attestations but cannot authenticate whether a
named approver is human. Host applications and organizational controls own
identity verification. The documented AI-agent contract prohibits
self-approval.

### 4.3 Decision maker

The decision view reports, in plain language:

- whether the weighting result is suitable for its declared use;
- population coverage and unresolved gaps;
- the extent of category collapsing;
- weight range, effective sample size, and design-effect consequences;
- material warnings and the responsible next decision;
- after weights are locked, how selected estimates differ between unweighted
  and weighted summaries.

It does not lead with solver terminology or imply that numerical convergence
establishes scientific validity.

### 4.4 Statistician

The statistical view exposes target tables, merge maps, residuals, weight
distributions, boundary contacts, effective sample size, design effects,
replicate uncertainty, sensitivity results, failure history, target provenance,
and analysis-ready tables. Every displayed value is derived from the same
structured result used by the decision view.

## 5. Architecture

One safe computation core serves both operator types and both reporting
audiences. Presentation layers may change wording, but they must not change
statistical defaults, permitted data, or results.

### 5.1 Design-only data

`wf_prepare_design()` creates a `wf_design_data` object. Its input table must
contain only assigned roles:

- record identifier;
- calibration dimensions;
- optional initial design weight;
- optional strata, cluster, and finite-population design fields.

Unassigned columns are blocking errors rather than silently retained or
dropped. This makes accidental inclusion of outcomes visible. The object stores
column roles, row count, schema identity, creation time, and data identity.

The function cannot infer the scientific meaning of a deceptively named field.
The operator remains accountable for declaring genuine design variables.

### 5.2 Verified external target

`wf_import_target()` reads a CSV or Excel evidence table and its source
metadata, validates them, and returns a `wf_verified_target`. Direct inline
numeric target vectors are not accepted by the safe workflow.

Required source metadata are:

- publisher or survey owner;
- dataset or table title;
- stable URI or complete citation;
- reference period;
- target population and geographic scope;
- retrieval date;
- applicable license or use authority;
- file checksum algorithm and value;
- documented transformation from source columns to WFC margins;
- operator attestation that the source and transformation were selected before
  study outcomes were examined.

WFC computes and records a SHA-256 checksum using a reviewed, cross-platform
implementation. Dependency and license review is required before choosing the
provider. A checksum protects identity and reproducibility; it does not prove
that the source is scientifically suitable.

`wf_target_template()` produces blank CSV and Excel templates. The package ships
a complete synthetic CSV example, a complete synthetic Excel example, matching
metadata, and runnable import code. Synthetic targets are marked `demo_only` and
are rejected for production-mode execution.

### 5.3 Precheck

The precheck verifies schema agreement, population scope, periods, category
coverage, empty and thin cells, target-total consistency, initial weights,
expected weight pressure, source completeness, and object identities. It reads
no analysis outcome.

### 5.4 Reviewable weight plan

`wf_plan_weights()` returns a `wf_weight_plan` without computing final weights.
It contains:

- proposed category merges and the design-only reason for each merge;
- affected records and population shares;
- unresolved support problems;
- selected calibration method and conservative defaults;
- proposed weight bounds and risk projections;
- identities of the design data, target evidence, parameters, and package;
- a stable plan identity.

The plan is deterministic for identical inputs. It must not automatically widen
bounds, relax targets, switch methods, or expand merge scope.

### 5.5 Separate approval and execution

`wf_approve_plan()` records the plan identity, approver, role, time, and note in
a `wf_plan_approval`. Approval is an explicit action separate from planning.
Any change to design data, target evidence, WFC version, or material parameters
invalidates the approval.

`wf_execute_plan()` requires a valid approval and returns locked weights. AI
agents may prepare the call but must not originate the accountable approval.
WFC records the attestation; an integrating host is responsible for identity
and authorization controls.

### 5.6 Attaching and assessing locked weights

`wf_attach_weights()` joins locked weights to full study data by identifier. It
does not plan, tune, or recompute weights.

`wf_assess_impact()` may compare predefined unweighted and weighted descriptive
estimates only after weight locking. It records the locked weight identity and
cannot feed results into `wf_plan_weights()` or `wf_execute_plan()`. A later
weight plan is a new audited run and cannot overwrite the earlier plan.

The initial impact interface covers documented proportions and means with
appropriate uncertainty support. It does not search for favorable outcomes or
choose which results to emphasize.

### 5.7 Reporting and audit

`wf_report()` continues to provide manager/decision and analyst/statistician
views. WFC 1.1 preserves the existing `manager` and `analyst` values and may add
clear aliases without changing their meaning. AI agents consume the structured
result object or audit export instead of parsing prose.

All views derive from a single immutable run record containing source evidence,
object identities, parameters, plan, approval, execution log, diagnostics,
package version, environment summary, and known nondeterminism.

## 6. Outcome-blind merge behavior

The safe merge planner may use:

- declared demographic or sampling dimensions;
- explicit ordered-category adjacency;
- unweighted sample support;
- initial design weights and proposed distortion bounds;
- province or other declared design boundaries;
- independent population cell support.

It must not use:

- outcome values or outcome counts;
- pass rates, scores, grades, satisfaction, or substantive study estimates;
- outcome similarity or heterogeneity;
- target intervals for study findings;
- an observed change in a study estimate.

Planning and applying remain two distinct steps. Guided automation may suggest a
plan but may not apply it without approval.

## 7. Conditions and failure policy

Conditions have three severities:

- **blocking:** execution stops and no force flag exists;
- **review required:** planning may continue, but the issue is visible before
  approval;
- **informational:** provenance and normal execution facts.

Each condition contains a stable code, severity, plain-language explanation,
affected object or field, structured evidence, and permitted next actions.
Chinese and English text may differ, but codes and payload fields are stable.

Blocking examples include missing provenance, scope mismatch, unassigned design
columns, invalid checksum, missing approval, stale approval, and unsupported
manual targets. Review-required examples include projected effective-sample-size
loss, broad collapsing, high weight ratios, and thin but estimable cells.

The system fails closed. It does not silently relax targets, widen bounds, change
methods, increase merge scope, ignore source defects, or convert a blocking
condition to a warning.

## 8. Capability disposition

### 8.1 ratecalib

| Capability | Disposition |
|---|---|
| Pass-rate, outcome-proportion, outcome-mean, or outcome-total targeting | Do not migrate |
| Exact or prioritized matching of user-supplied study-result targets | Do not migrate |
| Generic input and feasibility checks | Reimplement in WFC precheck |
| Weight bounds and diagnostics | Reuse WFC contracts and add missing diagnostics |
| Replicate-weight and uncertainty workflow | Map to WFC replicate and variance APIs |
| CSV/Excel handling | Reimplement only for verified external target evidence |
| Result methods | Use WFC result, report, tidy, and audit contracts |

### 8.2 mergecalib

| Capability | Disposition |
|---|---|
| Deterministic support-based candidate construction | Reimplement outcome-blind |
| Empty-cell absorption within declared design boundaries | Reimplement with reviewable plans |
| Conservation and weight-distortion checks | Reimplement in plan and audit validation |
| Outcome-grade interval constraints | Do not migrate |
| Outcome heterogeneity objective | Do not migrate |
| Target-driven relaxation and search expansion | Do not migrate |
| Consent/disclaimer gate | Replace with technical blocking and audit evidence |
| Exported merge maps and audits | Map to WFC plan and audit objects |

## 9. Version and migration plan

### 9.1 WFC 1.1 transition

WFC 1.1 adds the safe objects and workflow without breaking 1.0 calls. It emits
classed deprecation warnings on every use of:

- `wf_target_manual()`;
- `wf_target_shrink()`;
- inline `moments` in entropy balancing;
- manual-target pipeline modes and runtime manual margins.

The warning explains the scientific risk, names the safe replacement when one
exists, and states that removal is planned for WFC 2.0. Guided workflows default
to verified population or reference targets. Documentation and examples use
only the safe workflow.

At the same time, `mergecalib` and `ratecalib` stop feature development. Only
necessary security, correction, and archival work is permitted.

### 9.2 WFC 2.0 enforcement

WFC 2.0:

- requires `wf_design_data` and `wf_verified_target` in the supported workflow;
- removes manual target construction and target shrinkage from the supported
  public contract;
- removes inline arbitrary moment targets;
- removes manual pipeline target modes;
- provides no unsafe override or legacy compatibility shim;
- documents statistical and API incompatibility as a major-version change.

Categorical entropy calibration may remain when it operates only on verified
external margins. Arbitrary inline target moments do not remain.

### 9.3 Predecessor archival

Archival occurs only after WFC 2.0 release evidence and migration validation are
complete. Each predecessor repository will:

- state its retirement date, final supported version, and WFC successor;
- preserve Git history, tags, releases, license, and provenance;
- explain which capabilities have safe replacements and which intentionally do
  not;
- become read-only archived;
- follow the applicable package-index archival procedure if it has been
  distributed through CRAN or another index.

History is preserved rather than deleted. High-risk functions are documented as
having no replacement because the behavior is no longer supported.

## 10. Verification and statistical validation

### 10.1 Software verification

Tests must demonstrate that:

- incomplete source metadata and invalid checksums are rejected;
- unassigned columns in design input are rejected;
- production execution rejects demo-only targets;
- execution requires a matching, current approval;
- changed data, targets, parameters, or material package identity invalidate a
  plan or approval;
- identical inputs produce identical plans and weights;
- merges conserve records, target population totals, and defined weight totals;
- final weights are finite, positive, and within approved bounds;
- no silent relaxation, bound widening, method switching, or merge expansion
  occurs;
- CSV, Excel, Chinese, English, decision, statistician, and structured-agent
  paths are covered;
- WFC 1.1 deprecation and WFC 2.0 rejection match migration documentation;
- unsupported predecessor behaviors have no callable replacement path.

AI-generated implementation tests are not the sole oracle. Expected behavior is
specified independently in this design, analytic cases, trusted comparisons,
and human-reviewed fixtures.

### 10.2 Statistical validation

Validation includes:

- simulation scenarios for undercoverage, sparse categories, empty cells,
  inconsistent external totals, and extreme initial weights;
- comparison with a trusted implementation such as `survey` for supported
  external-margin calibration cases;
- sensitivity to approved bounds, minimum-cell rules, and collapse ladders;
- metamorphic tests showing that changing study outcomes cannot change a design
  plan or locked weights;
- regression comparisons for predecessor behavior that remains scientifically
  supported;
- adversarial tests demonstrating that pass-rate, study-result proportion,
  study-result mean, and outcome-interval targeting are unavailable;
- separate verification of numerical convergence and scientific suitability.

### 10.3 Presentation validation

Decision reports are reviewed for correct plain-language status, risk, and next
actions. Statistical reports are reconciled to structured result fields. Agent
contracts are tested by stable schema and condition codes, not by prose
matching.

## 11. Release gates

Each affected release must pass package tests, documentation generation,
license review, build checks, and `R CMD check` on supported environments.
Release evidence records source revision, dirty state, commands, runtime,
dependencies, input identities, checksums, generated artifacts, and validation
results.

WFC 2.0 is first released as a candidate. Before client or public reliance on
the changed statistical behavior, a qualified human statistician reviews the
relevant design, validation evidence, limitations, and migration consequences.
Accountable human approval is required; an AI assertion or AI-only review is not
sufficient.

Rollback means withdrawing the affected candidate or release and restoring the
last reviewed WFC artifact. It does not mean re-enabling prohibited behavior in
the safe workflow.

## 12. Security, data, licensing, and repository rules

- Tests and examples use only synthetic, public, or explicitly authorized data.
- Private or client data are not added to repositories or shared with AI tools.
- R code, generated help, tests, configuration, and commit messages remain in
  English; Chinese user guidance stays in the repository's approved localized
  documentation paths.
- Roxygen comments are the source of `NAMESPACE` and `man/`; generated files are
  not edited manually.
- Company copyright ownership and the GPL (>= 2) profile are preserved.
- New dependencies receive necessity, maintenance, security, and license review.
- Work proceeds on focused short-lived branches with deterministic evidence,
  material AI-assistance disclosure, statistical review, and protected-branch
  integration.

## 13. Limitations

WFC can enforce the supported data contract and create strong evidence of an
outcome-blind workflow. It cannot prevent a determined user from editing open
source code, fabricating provenance, mislabeling an outcome as a design
variable, or starting an unaudited workflow after examining results. The design
therefore combines technical restrictions with explicit provenance, separate
approval, immutable run identities, organizational review, and transparent
limitations. It reduces accidental and ordinary misuse and makes unsupported
behavior identifiable; it does not claim absolute prevention of fraud.

## 14. Acceptance criteria

The consolidation is complete only when:

1. WFC provides a usable, documented, bilingual safe workflow for practitioners
   and a stable structured workflow for AI agents.
2. The same result object produces reconciled decision and statistical views.
3. Weight planning and execution operate without access to study outcomes.
4. Only independently sourced, provenance-complete population or reference
   targets enter the supported workflow.
5. Cell merging is deterministic, support-based, reviewable, separately
   approved, and outcome-blind.
6. Locked weights can be attached to full study data without recalibration.
7. Post-lock outcome assessment cannot alter or overwrite the weight plan.
8. Prohibited outcome-targeting behaviors have no WFC 2.0 replacement path.
9. Engineering verification, statistical validation, migration evidence, and
   qualified human review are complete.
10. `mergecalib` and `ratecalib` are archived with preserved history and an
    accurate WFC successor notice.
