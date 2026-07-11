# WFCstudio Integration Contract

## Status and Ownership

This document freezes the WFC 1.0 integration boundary for the separate
WFCstudio sibling package. WFCstudio implementation does not live in the WFC
repository. Copyright in both the contract and the WFC project belongs to WEIAN
DATA TECH (Beijing) Co., Ltd.

The initial WFCstudio beta targets WFC `>= 1.0.0, < 2.0.0`. The core WFC
repository defines what the UI may call and what it may not compute; the sibling
package owns its own release, tests, and UI implementation.

## Architectural Rule

WFCstudio is a user interface over WFC, not a second statistical engine.

It may:

- ingest user-selected csv/xlsx files through sibling-package dependencies;
- collect mappings for dimensions, group keys, counts, IDs, and reviewed
  controls;
- construct ordinary arguments for exported WFC functions;
- call `wf_autoweigh()` and expert-path WFC functions;
- render structured WFC results, reports, ledgers, artifacts, plots, warnings,
  and classed errors;
- export user-authorized weights and reports.

It must not:

- implement raking, calibration, post-stratification, trimming, propensity,
  fusion, replication, or diagnostics;
- bypass `wf_precheck()` or catch and suppress blocking WFC conditions;
- invent collapse maps, ladders, bounds, or publication thresholds that the
  user did not review or declare;
- translate or rename stable WFC object fields, condition classes, actions, or
  ledger detail keys;
- write source data outside the user-selected session/export boundary.

## Minimum Workflow

The first beta workflow is:

1. Select sample and population files.
2. Map sample/population columns to `wf_dims()`, `key_map`, `count`, `by`, and
   `id` inputs.
3. Select a supported WFC language and guided controls.
4. Call `wf_autoweigh()` without changing its decisions.
5. Render the manager report and ordered decision ledger.
6. Allow inspection of precheck, collapse, trim, diagnostic, and report
   artifacts.
7. Export weights and the selected report only after explicit user action.

## Stable Inputs

WFCstudio targets the exported WFC 1.0 interfaces:

- `wf_dims()` and target constructors;
- `wf_autoweigh()`;
- `wf_report()` and plot methods;
- `as_svydesign()` / `as_svrepdesign()` for downstream ecosystem handoff;
- `wf_pipeline()`, `wf_run()`, `wf_validate()`, and `wf_audit_export()` for
  repeatable production rounds;
- `wf_autoweigh_result`, `wf_quality_report`, and WFC classed conditions.

The sibling package owns file-reading, reactive UI state, and presentation. It
passes ordinary data frames and scalar/list controls to WFC. Private source
files are never bundled with either package.

## Output Contract

The UI renders localized human-facing fields but preserves stable machine
fields:

- result `$method` and `$language`;
- ledger `step`, `action`, `detail_key`, `detail`, `artifact_class`, and `time`;
- manager-report English column keys and localized label/action values;
- artifact classes and classed condition names/payloads;
- exported unit `id`, `group`, `weight`, and `feature` fields.

WFCstudio may add presentation-only state outside these objects. It must not
mutate the WFC objects it receives.

## Localization

WFC remains the authority for localized weighting narration, report labels,
verdicts, actions, and plot labels. WFCstudio may read the installed DCF
catalogs for matching UI labels, but WFC catalog keys are not statistical
controls and never change programmatic semantics. Unsupported UI languages
fall back according to the WFC language contract.

## Conditions and Safety

WFCstudio reacts to WFC's stable condition classes:

- `wf_error_input`: highlight the invalid control;
- `wf_error_schema`: return the user to column/ID mapping;
- `wf_error_feasibility`: stop weighting and show the declared-remediation
  requirement;
- `wf_error_dependency`: explain the optional downstream package requirement;
- `wf_warning_data` / `wf_warning_quality`: render without suppressing.

No UI action may convert an error into a warning or continue after a blocking
condition unless WFC itself returns a successful result.

## Sibling-Package Release Gates

WFCstudio kickoff is complete only when its separate repository has:

- company ownership and WEIAN DATA commit identity enforcement;
- an explicit dependency on a compatible WFC release;
- contract tests using simulated WFC data only;
- bilingual UI coverage without translated stable keys;
- upload/export privacy tests;
- no statistical implementation outside WFC;
- an end-to-end beta flow against a real, user-authorized production cycle.

These remain external gates for the WFCstudio beta and do not add GUI code or
hard dependencies to the WFC core package.
