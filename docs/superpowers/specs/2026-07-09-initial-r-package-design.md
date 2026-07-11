# Initial R Package Build Design

## Goal

Build the first verifiable `weightflow` R package structure from the existing design document and core reference implementation. The first package version will be prepared for local checks and future GitHub publication, while keeping private source data out of git and out of the package tarball.

## Governing Inputs

- `weightflow_design.md` is the product and architecture authority.
- `weightflow_core.R` is the implementation reference for the 0.1.0 core.
- The existing spreadsheet and RData files are private source data. They must not be committed, shipped, or used as package example data.
- The project language policy is English for package internals, code, docs, tests, and configuration. The only allowed Chinese-language repository file is a root-level Chinese overview file.

## Architecture

The repository root becomes the R package root. The package name is `weightflow`, version starts at `0.1.0`, and the core remains dependency-light with no required runtime imports beyond base R and recommended R packages.

Planned package layout:

```text
DESCRIPTION
NAMESPACE
R/
tests/testthat/
data-raw/
inst/
docs/
AGENTS.md
README.md
README.zh-CN.md
.gitignore
.Rbuildignore
```

The original design and prototype files will be migrated into English paths. The design document must live under `inst/design/`. The prototype implementation will be retained under `inst/reference/` for auditability, while the package implementation lives under `R/`.

The first build exports only implemented, tested functions. Future public API names from the design document remain roadmap items unless they are implemented and covered by tests in this pass.

## Components

The reference implementation must be split into focused R files without changing the public behavior unless tests expose a bug:

- `R/utils.R`: internal helpers for character key normalization, schema checks, grouped sums, and target validation.
- `R/conditions.R`: `wf_abort()` and `wf_warn()` classed condition helpers.
- `R/dims.R`: `wf_dims()`.
- `R/target.R`: canonical target construction through `wf_target_population()` and `wf_target_reference()`.
- `R/precheck.R`: `wf_precheck()` and `print.wf_precheck()`.
- `R/collapse.R`: `wf_apply_collapse()`.
- `R/rake.R`: `wf_rake()` and `print.wf_weights()`.
- `R/diagnostics.R`: `wf_diagnose()` and `print.wf_diagnostics()`.

All exported symbols must use the `wf_` prefix. Internal helper names may use a leading dot or unexported `wf_` names, but must not expand the public API casually.

## Data And Git Policy

The existing source data files are private and non-uploadable. They must be excluded from git and from package builds. Package examples and tests must use a newly generated, small, simulated dataset with no dependency on private files.

Required data handling:

- Keep private source data outside tracked package data.
- Put simulation scripts under `data-raw/`.
- Save a small simulated package dataset as `data/weightflow_example.rda`.
- Ignore spreadsheet and RData source formats by default.
- Add `.Rbuildignore` entries for development-only files, raw private data, CodeGraph files, and local build artifacts.

## Documentation

`README.md` must describe the package purpose, the precheck -> execute -> diagnose workflow, the data policy, and a minimal simulated example. `AGENTS.md` must be a handoff file for future agents and contributors, covering design authority, language policy, data policy, test policy, and safe git behavior.

`README.zh-CN.md` must be concise and located at the repository root. It is the only Chinese-language file allowed by project policy.

R documentation must be generated with roxygen2. Each exported function must have concise examples that run on simulated data and do not require private files.

## Tests

Use `testthat` for behavior-driven package tests. The first test suite must cover:

- `wf_dims()` rejects unnamed dimensions and collapse ladders for unknown dimensions.
- target constructors reject missing columns and invalid target counts.
- target construction enforces the additivity invariant.
- `wf_precheck()` reports blocking issues for unknown sample categories, infeasible positive target cells, duplicate IDs, and overloaded missingness.
- `wf_rake()` refuses blocked prechecks.
- `wf_rake()` returns positive weights and matches group totals and margins on simulated data.
- `wf_diagnose()` reports ESS, design effect, verdict, and margin error.
- ignore and build-ignore rules protect private source data from publication.

The implementation must follow test-driven development for production behavior changes: write or port the test first, confirm it fails for missing behavior or catches the current defect, then implement the minimal code and rerun the test.

## Verification

The first build is not complete until these commands have been run freshly and their output inspected:

```bash
Rscript -e 'devtools::test()'
Rscript -e 'devtools::document()'
R CMD check --no-manual .
git status --short
```

If a command fails because a local optional package is missing, do not install dependencies automatically. Report the missing package and either use a narrower installed-tool verification path or ask for approval to install.

## Scope Boundaries

This first build does not attempt to implement every roadmap API in `weightflow_design.md`. In particular, manual targets, shrinkage, collapse suggestions, weight composition, online/offline blending, replicate weights, optional `survey` comparisons, and CI publishing are future work unless they are explicitly added to a later approved plan.

The build must not delete source materials. Existing non-English source folders can be migrated to English paths during implementation, but private source data must remain recoverable locally and must not be committed.

## Acceptance Criteria

- The repository is a valid local R package.
- Package internals are English-only except for the single root-level Chinese overview file.
- Private source data is excluded from git and package builds.
- The implemented API is documented and tested.
- Package checks are run or any blocker is reported with exact command output.
- Git history starts with intentional commits and does not include private data.
