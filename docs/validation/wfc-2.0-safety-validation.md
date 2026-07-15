# WFC 2.0 Safety Validation

## Status and scope

This document records software verification evidence for the WFC 2.0 release
candidate. It does not certify a real survey, a source, a weighting decision, or
a public/client analysis. The synthetic reviewer name used by the runner exists
only to exercise code paths and is not human approval evidence.

WFC reduces accidental and routine misuse at its supported public boundary. It
does not prove source truth, detect a deliberately false evidence record, judge
whether a variable is scientifically appropriate merely from its name, or stop
someone from copying and modifying open-source code. Those limits require
accountable human governance.

## Reproducibility record

- Validation date: 2026-07-15 (Asia/Kuala_Lumpur)
- Candidate identifier: `v2.0.0-rc.1` (candidate only; not a public release)
- Source revision before adversarial-evidence edits:
  `b525308376ac6be78389a69b0005a852e60b0c14`
- Source state: the WFC 2.0 contract, removals, boundary enforcement, and current
  documentation migration were committed. The adversarial runner, its contract
  test, this report, and release-candidate metadata were uncommitted evidence
  changes during the recorded run.
- Random seed: `20260715`
- R: 4.6.0 (2026-04-24)
- Platform: `aarch64-apple-darwin23`, macOS Tahoe 26.5.2
- Locale: `C.UTF-8`; time zone: `Asia/Kuala_Lumpur`
- Relevant packages: `survey` 4.5, `testthat` 3.3.2, `pkgload` 1.5.3,
  `digest` 0.6.39, `openxlsx` 4.2.8.1, `rmarkdown` 2.31, and `knitr` 1.51.

Commands observed so far:

```sh
Rscript tests/validation/validate-wfc-2-safety.R
R_LIBS=/private/tmp/wfc-r-lib WFC_REQUIRE_SURVEY=true \
  Rscript tests/validation/validate-safe-workflow.R
R_LIBS=/private/tmp/wfc-r-lib \
  Rscript -e 'testthat::set_max_fails(Inf); devtools::test()'
R_LIBS=/private/tmp/wfc-r-lib R CMD build .
R_LIBS=/private/tmp/wfc-r-lib \
  R CMD check WFC_2.0.0.tar.gz --as-cran
```

## Adversarial refusals

The runner traces all five internal weighting engines. For each adversarial
attempt, `engine_calls_before_refusal` and the count after refusal were both 0.

| Scenario | Expected and observed result | Engine calls | Result |
| --- | --- | ---: | --- |
| `manual_margins` | `manual_pipeline_unsupported` | 0 | Pass |
| `pass_rate_target` | `verified_weighting_inputs_required` | 0 | Pass |
| `outcome_mean` | `inline_moments_unsupported` | 0 | Pass |
| `outcome_interval` | `verified_weighting_inputs_required` | 0 | Pass |
| `unverified_target` | `verified_weighting_inputs_required` | 0 | Pass |
| `demo_target` | `demo_target_in_production` | 0 | Pass |
| `target_selected_after_outcomes` | `target_selected_after_outcomes` | 0 | Pass |
| `stale_approval` | `plan_approval_mismatch` | 0 | Pass |
| `changed_design` | `execution_design_mismatch` | 0 | Pass |
| `agent_approval` | `human_approval_required` | 0 | Pass |
| `raw_public_engine_call` | `verified_weighting_inputs_required` | 0 | Pass |
| `runtime_margins_argument_removed` | `margins` absent from `wf_run()` | 0 | Pass |

Here, `raw_public_engine_call` means calling the exported weighting wrapper with
a raw data frame. Internal functions reached through `:::` are implementation
details, not a security sandbox. The supported API boundary and repository
tests are the enforceable software contract.

## Numerical and regression evidence

The existing controlled validation passed all 15 checks with `survey` required.
It covered repeatable plans and weights, positive bounded weights, conservation,
outcome isolation after locking, declared merging for sparse cells, target
tampering, and an extreme base weight. WFC weighted margins differed from the
independent `survey` tables by at most `7.8e-12`, below tolerance `1e-6`.

The final source-tree package run with `survey` available passed 1,110 checks
with 0 failures, 0 warnings, and 0 skips.

## Candidate build and check

The WFC 2.0.0 source package built successfully, including all vignettes. Its
SHA-256 was
`bf04cc52be7ce86bbd9a77a7e18db73821332240594d9fa46b84d07661b5baa2`.

The final `R CMD check WFC_2.0.0.tar.gz --as-cran` result was:

- 0 errors;
- 0 warnings; and
- 2 notes.

The installed-package test phase passed 993 checks and skipped 8 repository-only
checks whose source READMEs, migration report, validation report, `.gitignore`,
or `.Rbuildignore` are intentionally excluded from the CRAN tarball. The safety
contract under `inst/stability` was tested from its installed location.

The two notes were reviewed:

1. `New submission`, expected because WFC has not previously been published on
   CRAN.
2. HTML validation was skipped because the local external HTML Tidy executable
   was not recent enough. The PDF manual, examples, tests, source and rebuilt
   vignettes, documentation, and package loading checks passed.

An initial candidate check exposed repository-relative paths in three contract
tests. Those tests were changed to read the installed safety contract or skip
repository-only documents, the tarball was rebuilt, and the complete check above
was rerun from the new tarball.

## Sensitivity and limitations

The tests demonstrate refusal order for the named supported entry points; they
do not establish that every possible outcome proxy can be recognized from
arbitrary column names or metadata. A person can lie in `selected_before_outcomes`,
misdescribe a source, or edit package objects and source code. SHA-256 identities
show that recorded artifacts did not change; they do not show that the artifacts
were truthful or scientifically suitable.

The numerical scenarios do not cover every sampling design, nonresponse
mechanism, population misspecification, rare-category structure, variance
estimator, or source-data quality problem. Package-level evidence never
authorizes a particular analysis. Each consequential analysis still requires
review of its source, design roles, proposed merges, diagnostics, exact plan,
and audit record.

## Human review gate

- WFC 2.0 accountable release approval: **pending**
- WFC 2.0 qualified human statistical review: **pending**
- Required review scope: all WFC 2.0 retained functions, removed-interface
  behavior, adversarial evidence, numerical validation, migration guidance, and
  release candidate.
- Public/client reliance authorized: **no**
- Predecessor-package archival authorized by this record: **no**

Jinyan Zhu's qualified review completed on 2026-07-15 applies to WFC 1.1. It is
not reused as WFC 2.0 approval. Kunxiang Ma's WFC 1.1 release approval likewise
does not approve WFC 2.0. These WFC 2.0 gates must be recorded separately after
the candidate is available for review.
