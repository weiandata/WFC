# Predecessor-package archival gate

## Decision

This record confirms that the release gate required before retiring
`mergecalib` and `ratecalib` has been met. WFC 2.0.0 is the maintained
successor for the defensible capabilities listed below. Capabilities that use
study results, desired findings, or outcome-driven optimization were
intentionally not migrated and have no supported replacement.

This is a package-level lifecycle decision. It does not authorize a specific
survey, weighting plan, public analysis, or client deliverable. Each
consequential analysis still requires review of its source evidence, design
roles, proposed cell merges, diagnostics, exact approved plan, and audit
record.

## Successor release evidence

- Release: WFC 2.0.0
- Release date: 2026-07-15
- Annotated tag: `v2.0.0`
- Release commit: `4cd0347706d9dcbfe5f0030612adab9ec648fc9c`
- Release page: <https://github.com/weiandata/WFC/releases/tag/v2.0.0>
- Source artifact: `WFC_2.0.0.tar.gz`
- Artifact SHA-256:
  `74a76b6b412784ddbb389fc11932422b0e8499415669385095238ca17412d44c`
- Final local source-tree tests: 1,111 checks, 0 failures, 0 warnings,
  0 skips
- Final adversarial validation: 12 of 12 refusals passed, with zero weighting
  engine calls before refusal
- Final controlled statistical validation: 15 of 15 checks passed; maximum
  difference from independent `survey` estimates was `7.8e-12`
- Final `R CMD check --as-cran`: 0 errors, 0 warnings, 2 reviewed notes
- GitHub release asset digest: matched the SHA-256 recorded above
- Release and post-merge continuous-integration checks: passed on Linux R
  devel/release/oldrel, macOS, and Windows

The detailed software evidence and limitations are in
[`wfc-2.0-safety-validation.md`](wfc-2.0-safety-validation.md). The safe import
examples and the WFC 1.x migration boundary are in the repository
[`README.md`](../../README.md), especially “Bring your own population data”
and “Migration from WFC 1.x”. The approved design and full predecessor
capability disposition are in
[`2026-07-15-safe-package-consolidation-design.md`](../superpowers/specs/2026-07-15-safe-package-consolidation-design.md).

## Human review and release approval

- Independent reviewer: Jinyan Zhu
- Professional qualification: statistical expert
- Review completed: 2026-07-15
- Review scope: all WFC 2.0 functionality
- Accountable release approver: Kunxiang Ma
- Approver role: company legal representative
- Release authorization: granted on 2026-07-15

The identities, qualification, date, scope, and approval were supplied by the
accountable project representative. No signed external review document is
stored in this repository.

## `mergecalib` capability disposition

The following defensible capabilities are covered by supported WFC 2.0
workflows:

| Predecessor capability | WFC 2.0 disposition |
| --- | --- |
| Deterministic, outcome-blind cell support assessment and merge planning | Use `wf_plan_cells()` with an explicit merge ladder, minimum cell size, and maximum merge ratio. The plan remains reviewable before application. |
| Import of external population targets from CSV or Excel | Use `wf_import_target()` after source verification. Use `wf_import_reference()` when the evidence is an external reference sample. The README provides copyable import examples for survey researchers and AI agents. |
| Calibration, raking, post-stratification, soft calibration, and categorical entropy calibration | Supported only with verified external population or reference margins through the corresponding WFC weighting functions. |
| Conservation, weight distortion, effective sample size, and balance diagnostics | Use WFC diagnostics and `wf_report()`; retain machine-readable evidence through WFC result and audit objects. |
| Merge maps and audit records | Use the reviewable cell plan and `wf_audit_export()`. |
| Replicate-weight and variance workflows | Use WFC replicate and variance interfaces after the weighting plan has passed its required review. |

The following capabilities were intentionally not migrated:

- outcome-grade interval constraints;
- outcome-heterogeneity optimization;
- target-driven relaxation or minimum-delta widening; and
- any merge, calibration, bound, or search decision selected after examining
  study outcomes.

These behaviors have no supported replacement in WFC. WFC does not provide a
compatibility switch, workaround, or unsafe override for them.

## `ratecalib` capability disposition

The following generic and defensible capabilities are covered by supported WFC
2.0 workflows:

| Predecessor capability | WFC 2.0 disposition |
| --- | --- |
| Generic data validation and feasibility checks | Use `wf_prepare_design()` and `wf_precheck()` with declared design roles. |
| Bounded weighting to verified external population margins | Use `wf_calibrate()`, `wf_rake()`, or `wf_poststrat()` with a verified target object and an approved plan. |
| Weight, balance, and feasibility diagnostics | Use `wf_diagnose()` and the detailed output of `wf_report()`. |
| Replicate weights and variance estimation | Use `wf_replicates()` and `wf_variance()`. |
| CSV or Excel target import | Use `wf_import_target()` or `wf_import_reference()` only after verifying the external source. The README contains copyable examples for both human users and AI-agent integrations. |
| Human-readable and machine-readable results | Use the concise decision view of `wf_report()` for decision-makers and its detailed result/audit objects for statistical review and further analysis. |

The following capabilities were intentionally not migrated:

- calibration to user-supplied pass-rate targets;
- calibration to study-result proportions, means, or totals;
- exact or prioritized matching of desired study results;
- arbitrary inline outcome moments; and
- targets, priorities, or bounds selected after examining study outcomes.

These behaviors have no supported replacement in WFC. WFC does not provide a
compatibility switch, workaround, or unsafe override for them.

## Archival authorization boundary

This gate authorizes preparation and ordinary review of retirement commits in
the two predecessor repositories. It does **not** itself authorize changing the
GitHub repositories to read-only archived state. That external lifecycle change
requires immediate, explicit organization-owner approval after the retirement
commits are on the default branches, their checks pass, package-index status is
recorded, and the exact predecessor commit identifiers are available for final
review.

Archival must preserve Git history, tags, releases, licenses, copyright and
provenance records. It must not delete, transfer, hide, or rewrite either
repository.

## Archive completion audit

The accountable organization owner, Kunxiang Ma, gave immediate explicit
approval on 2026-07-15 to archive the two predecessor GitHub repositories. The
approval was limited to setting the repositories to GitHub read-only Archived
state. It did not authorize deletion, transfer, visibility changes, history
rewrites, or removal of branches, tags, releases, licenses, copyright, or
provenance.

The final states recorded through the GitHub API were:

| Repository | Final `main` commit | Archive time | Visibility | Result |
| --- | --- | --- | --- | --- |
| `weiandata/mergecalib` | `4b55f356b58dab3140a4ab1f2066f07eb177fb68` | 2026-07-15 18:55:30 Asia/Kuala_Lumpur (10:55:30 UTC) | Private, unchanged | `archived: true` |
| `weiandata/ratecalib` | `9d400099a61afc08b950f9e11965c649c9b157ec` | 2026-07-15 18:55:39 Asia/Kuala_Lumpur (10:55:39 UTC) | Public, unchanged | `archived: true` |

- Operator: Codex, using the authenticated GitHub account
  `makunxiang-weiandata` under the owner's explicit approval.
- Method: GitHub REST repository update setting only `archived=true`.
- Both local `main` branches were clean and identical to `origin/main` before
  the lifecycle change.
- Both final authorization pull requests passed their repository checks and
  cross-platform R checks before merge. The resulting `main` commits then
  passed the post-merge checks before archival.
- Immediately before archival, each repository had only the `main` branch,
  no open issue, no open pull request, and no tag or GitHub Release to remove.
- Immediately after archival, the GitHub API reported `archived: true`, each
  `main` branch remained readable at the exact commit above, and each README
  remained readable. No write test was attempted against the archived
  repositories.
- WFC remained active and unarchived. The WFC 2.0.0 release and its source
  artifact remained available with SHA-256
  `74a76b6b412784ddbb389fc11932422b0e8499415669385095238ca17412d44c`.

### CRAN follow-up for `ratecalib`

The active CRAN index still listed `ratecalib` 0.3.0 on the verification date.
Its CRAN `URL` and `BugReports` fields pointed to the maintainer's personal
repository `makunxiang-cmd/ratecalib`, not to `weiandata/ratecalib`, and the
active CRAN index showed no reverse dependencies. The registered maintainer
reported sending the plain-text archive request to `CRAN@R-project.org` at
2026-07-15 18:41 Asia/Kuala_Lumpur (10:41 UTC).

CRAN receipt or archival confirmation had not yet been supplied when the
GitHub repositories were archived. The accountable owner explicitly approved
proceeding with GitHub archival while that external confirmation was pending.
When CRAN responds, the response date and resulting index status must be added
to this maintained WFC record; the predecessor repository must not be reopened
merely to add the CRAN follow-up.
