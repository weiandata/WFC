# CRAN submission readiness

## Decision

WFC 2.0.0 is in a CRAN-submittable state. `R CMD check --as-cran` is clean
apart from expected, explained notes, and the same result was confirmed on the
official Windows builder. This record captures the evidence gathered before the
first CRAN upload. It does not itself perform the upload; submission via the
CRAN web form and the maintainer's email confirmation remain a maintainer
action.

## Artifact under review

- Package: WFC 2.0.0
- Source commit: `e6e7b82` (`main`, merge of PR #8)
- Source artifact: `WFC_2.0.0.tar.gz`
- Artifact SHA-256:
  `039cc400ada262bec86f573f0e0dc5e19db1b2fd59243ae295bbdedf8c0d23be`

The `Packaged:` timestamp line in `DESCRIPTION` changes on each build, so a
freshly rebuilt tarball has a different whole-file SHA-256 while every other
file is byte-identical.

## Local `R CMD check --as-cran`

Run under both `en_US.UTF-8` and `zh_CN.UTF-8` sessions, with `survey` 4.5
available; results were identical in both locales:

- 0 errors
- 0 warnings
- 2 notes, and `FAIL 0 | WARN 0 | SKIP 8 | PASS 993`

The notes were:

1. `New submission`. Expected, because WFC has not previously been published on
   CRAN.
2. `Skipping checking HTML validation: 'tidy' doesn't look like recent enough
   HTML Tidy.` This concerns the local external HTML Tidy executable, not the
   generated R documentation, and does not appear on the Windows builder.

## Windows builder (win-builder)

`WFC_2.0.0.tar.gz` was checked on <https://win-builder.r-project.org>. The
per-run log URLs are ephemeral (removed after roughly 72 hours), so only the
outcomes are recorded here.

- First round, R-devel and R-release: `Status: 1 NOTE` each. The note body was
  `New submission` plus two sub-items:
  - possibly misspelled words in `DESCRIPTION`; and
  - a possibly invalid file URI, `docs/migration/wfc-1-to-2.md`, linked from
    `README.md`.
- Fix (PR #8, commit `d312d44`): both `README.md` and `README.zh-CN.md` now
  link to the migration guide by its full GitHub URL. `docs/` is
  `.Rbuildignore`d, so the previous repository-relative link could not resolve
  from the installed package.
- Re-check, R-devel: `Status: 1 NOTE`. The note body was `New submission` plus
  the possibly-misspelled-words sub-item only; the invalid file URI was gone.

The words flagged as possibly misspelled are spelled correctly: `Deville`,
`Saerndal` and `Hainmueller` are cited author surnames (see the DOIs in
`DESCRIPTION`), and `precheck` and `predeclared` are established package terms.

## Continuous integration

GitHub Actions passed on Linux (R devel, release, oldrel-1), macOS (release),
and Windows (release), plus the coverage and Markdown jobs, on both PR #7 and
PR #8.

## Fixes landed for CRAN readiness

- PR #7 (`fix(tests)`, commit `2dcb086`): made the test suite independent of the
  session locale. The suite previously assumed an English session and failed 9
  tests under `zh_CN.UTF-8`, which is the maintainer machine's default locale.
- PR #8 (`docs(readme)`, commit `d312d44`): replaced the repository-relative
  migration-guide link with its full GitHub URL and recorded the
  misspelled-words clarification in `cran-comments.md`.

## Submission

The maintainer reported that WFC 2.0.0 was submitted to CRAN through the web
form on 2026-07-18 and is awaiting review. Evidence form: the maintainer
reported the submission in the project task; no submission receipt or email is
stored in this repository. This records that the upload was made, not that CRAN
has accepted or indexed the package.

## Remaining boundary

The DOIs in `DESCRIPTION` were confirmed against CrossRef to resolve to the
cited Deville and Saerndal (1992) and Hainmueller (2012) papers. The resulting
CRAN index status must be recorded here once CRAN processing completes, whether
the package is accepted, archived, or requires a resubmission.
