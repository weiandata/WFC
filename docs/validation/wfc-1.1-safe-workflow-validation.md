# WFC 1.1 Safe-Workflow Validation

## Status and scope

This document records software verification evidence for the WFC 1.1 safe
workflow. It does **not** certify a real survey, population source, weighting
decision, or a specific public/client use. Accountable release approval and
independent review by a qualified statistical expert were completed separately
from the software checks and are recorded below.

The approval objects created by the validation runner use synthetic names and
test-only data solely to exercise the identity and execution controls. They are
not human approval evidence and must not be represented as such.

## Reproducibility record

- Validation date: 2026-07-15 (Asia/Kuala_Lumpur)
- Source revision before release-evidence edits:
  `7f9a53ae043e0b20a95dd586c43274a8f6a4b566`
- Source state: the implementation through Task 10 was committed; the validation
  runner, CI enforcement, this report, and release metadata were uncommitted
  release-evidence changes during the recorded run.
- Random seed: `20260715`
- R: 4.6.0 (2026-04-24)
- Platform: `aarch64-apple-darwin23`, macOS Tahoe 26.5.2
- Locale: `C.UTF-8`; time zone: `Asia/Kuala_Lumpur`

Commands:

```sh
Rscript tests/validation/validate-safe-workflow.R
R_LIBS_USER=/tmp/wfc-r-lib WFC_REQUIRE_SURVEY=true \
  Rscript tests/validation/validate-safe-workflow.R
```

The first command passed all 15 recorded checks and correctly reported that the
optional local `survey` comparison was skipped. After installing `survey` 4.5
and its dependencies into a temporary library, the second command passed all 15
checks with the reference comparison required.

## Observed scenarios

| Scenario | Evidence observed | Result |
| --- | --- | --- |
| Supported undercoverage | Cell-plan and weight-plan identities repeated exactly; repeated weights had maximum absolute difference 0 | Pass |
| Weight validity | Locked weights were finite and positive; range 0.72949 to 1.45898; relative-to-mean range 0.72949 to 1.45898 | Pass |
| Conservation | Supported scenario weighted total was 40, equal to the imported target total | Pass |
| Outcome isolation | Reversing outcome values changed the post-lock impact summary but left the locked-weight identity unchanged | Pass |
| Sparse/empty cells | Explicit age-collapse ladder resolved the empty category; sample count 12 and base-weight total 12 were conserved | Pass |
| Inconsistent/tampered target | Changing a target margin after import was blocked with `wf_error_safety` before planning | Pass |
| Extreme base weight | Declared category merging produced positive weights; relative-to-mean range 0.657287 to 3; weighted total remained 40 | Pass |
| `survey` reference | WFC weighted sex and age margins differed from `survey` tables by at most `7.8e-12`, below tolerance `1e-6` | Pass |

CI sets `WFC_REQUIRE_SURVEY=true` and installs `survey`, so an absent reference
package or failed comparison is a validation failure rather than a skip.

## Dependency review

- `digest` 0.6.39 remains necessary as an imported dependency for SHA-256 file
  and object identities. Its installed license is GPL (>= 2), compatible with
  WFC's GPL (>= 2) license. The installed metadata records a 2025-11-19
  publication, a named maintainer, and a public issue tracker. It is narrowly
  used; retaining it avoids platform-specific shell hashing and preserves
  deterministic audit identities.
- `openxlsx` 4.2.8.1 remains optional (`Suggests`) and is used only when a user
  imports or writes Excel templates. Its installed license is MIT + file LICENSE.
  The installed metadata records a 2025-10-31 publication, a named maintainer,
  and a public issue tracker. CSV remains dependency-free and is the default
  documented interchange format.
- `survey` 4.5 remains optional (`Suggests`) for ecosystem conversion and
  independent numerical comparison. It is mandatory in validation CI but is not
  required by the core safe workflow at runtime.

No new network, database, browser, or executable dependency is introduced by
the safe workflow. Package versions above describe the validation environment,
not minimum runtime pins. This review checks necessity, installed metadata,
license, compilation boundary, and the availability of public issue reporting;
it is not a claim that no undisclosed vulnerability can exist. Both `digest`
and `openxlsx` contain compiled code, so ordinary dependency update and security
monitoring remain required.

## Full package verification

After updating the package version and release documentation, the following
commands were observed:

```sh
R_LIBS_USER=/tmp/wfc-r-lib Rscript -e 'devtools::document()'
R_LIBS_USER=/tmp/wfc-r-lib Rscript -e 'devtools::test()'
R_LIBS_USER=/tmp/wfc-r-lib R CMD build .
R_LIBS_USER=/tmp/wfc-r-lib R CMD check WFC_1.1.0.tar.gz --as-cran
```

- Documentation generation: pass.
- Full test suite: 1,020 passed; 0 failed; 0 warnings; 0 skipped.
- Source build, including vignettes: pass.
- `R CMD check --as-cran`: 0 errors, 0 warnings, 2 notes.
- Notes reviewed: expected `New submission`; local HTML validation skipped
  because the installed external HTML Tidy was not recent enough. PDF manual,
  examples, tests, vignettes, and regenerated vignette outputs passed.

## Sensitivity and limitations

The simulations deliberately cover supported undercoverage, an empty target
category, a mutated target identity, and one extreme base weight. They verify
determinism, bounds, conservation, blocking order, and outcome isolation. They
do not establish estimator performance for every sampling design, nonresponse
mechanism, population misspecification, rare-category structure, variance
estimator, or real source-data quality problem.

Before public or client reliance on a specific analysis, an accountable person
must verify that analysis's external source and transformation, review the
proposed category merges and diagnostics, approve the exact plan, and retain the
audit record. The package-level review recorded below does not replace those
analysis-specific controls. Reviews are never complete merely because package
tests or this script pass.

## Human review gate

- Accountable release approval: **completed**
- Approver: Kunxiang Ma
- Approver role: company legal representative
- Approval date: 2026-07-15
- Approved decision: release WFC 1.1.0 and proceed to the next controlled stage
- Independent qualified statistical review: **completed**
- Reviewer: Jinyan Zhu
- Reviewer qualification: statistical expert
- Review completion date: 2026-07-15
- Review scope: all WFC 1.1 functionality
- Evidence form: identities, roles, date, scope, and decision were supplied by
  the accountable project representative for this repository record; no signed
  external review document is stored in the repository.
- Package release authorized: **yes**
- Any specific public/client analysis authorized solely by this document: **no**
