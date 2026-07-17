# CRAN comments

## Test environments

* Local: macOS Tahoe 26.5.2, R 4.6.0 (aarch64-apple-darwin23)
* GitHub Actions: R devel, release, and oldrel-1 on Linux; R release on
  macOS and Windows

## Release

This is the initial CRAN submission for WFC, now at version 2.0.0. The package
was previously developed under the name `weightflow`, but that package name is
already in use on CRAN by an unrelated package. Version 1.0.0 froze the public
WFC core API. Version 1.1.0 adds verified external target import, outcome-blind
planning, identity-bound human approval, locked-weight execution, post-lock
impact assessment, and auditable reports. Version 2.0.0 makes that verified
workflow mandatory for weight construction and removes subjective manual
targets, target shrinkage, inline moment targets, manual pipeline targets, and
run-time margin injection without a compatibility switch.

WFC is distributed under GPL (>= 2); `inst/COPYRIGHTS` records the copyright
boundary for separately distributed optional dependencies.

## R CMD check results

Local `R CMD check WFC_2.0.0.tar.gz --as-cran`:

* 0 errors
* 0 warnings
* 2 notes

The notes were:

1. `New submission`. This is expected because WFC has not previously been
   published on CRAN.
2. `Skipping checking HTML validation: 'tidy' doesn't look like recent enough
   HTML Tidy.` The local checker completed the PDF manual and all package,
   documentation, example, test, and vignette checks. This note concerns the
   local external HTML Tidy executable rather than generated R documentation.

There are no downstream dependencies because this is a first submission.

The check was run under both an `en_US.UTF-8` and a `zh_CN.UTF-8` session and
reported the same result in each. WFC localizes its reports, so the test suite
pins the report language and neutralizes the session locale rather than
inheriting it.

## Examples

Most exported functions are documented without executable examples, and
`wf_report()` keeps one `\dontrun{}` block. This is a deliberate safety
property of the package rather than an oversight, and we would appreciate
guidance if CRAN would prefer a different presentation.

WFC constructs weights only from an external population target whose evidence
record has been verified, and only after an identified human has approved the
resulting plan. Two consequences follow:

1. The bundled example target ships with `demo_only` status. It can demonstrate
   import and checksum verification, and `wf_prepare_design()` and
   `wf_import_target()` carry running examples that also show the
   corresponding refusals, but by design that target cannot enter planning. No
   synthetic file shipped with the package is permitted to impersonate an
   authoritative population source, so a self-contained example cannot
   legitimately reach `wf_plan_weights()`, `wf_calibrate()`, `wf_rake()` or the
   diagnostics that consume locked weights.
2. `wf_approve_plan()` records an accountable human reviewer's identity. An
   example that supplied that identity would be an automated process attesting
   a human review, which is exactly what the package is built to prevent.

The full workflow is therefore demonstrated, with the same reasoning stated
inline, in the `safe-weighting-workflow` vignette. The gated steps appear there
as unevaluated but copy-runnable code. Package behavior is covered instead by
the test suite, which exercises the complete path, including planning,
approval, execution and reporting, against fixtures that are confined to the
tests and never installed as usable authority.

## Additional verification

* Twelve adversarial checks cover manual margins, pass-rate and outcome targets,
  unverified and demo targets, selection after outcomes, stale approvals,
  changed design data, AI-agent approval, and raw public weighting calls. Every
  attempt stopped before a weighting engine was invoked.
* A deterministic controlled validation covers supported undercoverage,
  sparse/empty cells, tampered targets, extreme base weights, outcome isolation,
  bounds, and total conservation. With `survey` 4.5, WFC's weighted margins
  differed from the independent `survey` tables by at most `7.8e-12`.
* CI installs `survey` and makes the numerical reference comparison mandatory.
  Independent statistical review of all WFC 2.0 functionality was completed by
  Jinyan Zhu, statistical expert, on 2026-07-15. Accountable release approval was
  completed by Kunxiang Ma, company legal representative. These package-level
  decisions remain separate from analysis-specific review and approval.
* CI enforces at least 80% line coverage.
* The full source-tree suite passed 1,111 checks with `survey` available. Verified
  boundary tests cover raking, bounded logit, post-stratification, declared
  remediation, trim review, input immutability, localized narration, and stable
  decision-ledger keys.
* English and Simplified Chinese catalogs are checked for key parity. Plot
  methods are exercised on non-interactive PDF devices, and the report suite
  verifies localized structured, Markdown, escaped standalone HTML, and file
  output.
* Survey interoperability tests verify exact, order-independent ID alignment,
  survey design metadata, and downstream weighted estimates. Replicate bridge
  tests prove `survey::svymean()` standard errors equal `wf_variance()` for
  bootstrap, JK1/JKn, and BRR designs.
* Broom-style methods are tested through the suggested `generics` package and
  return base data frames; WFC has no hard survey, srvyr, generics, broom,
  tibble, or dplyr dependency.
* Package examples and vignettes use only the bundled simulated `wfc_example`
  data. Files under `private-data/` are excluded from builds and are never read
  by examples or tests.
* WFCstudio is a separate sibling package. The WFC core package contains only
  the integration contract and has no GUI, Shiny, xlsx, or other hard UI
  dependency.
