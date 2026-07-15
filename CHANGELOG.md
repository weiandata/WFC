# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing package changes are recorded in R-native form in
[NEWS.md](NEWS.md), which is the detailed changelog shipped with the package.
This file tracks repository-level milestones.

## [Unreleased]

### Removed

- Remove subjective manual targets, target shrinkage, inline moment targets,
  manual pipeline targets, and run-time margin injection without a compatibility
  switch.
- Remove all supported paths from raw samples or ordinary target objects to a
  weighting engine.

### Changed

- Require unchanged design-only data, verified external target evidence,
  deterministic planning, qualified human approval, and locked execution for
  WFC 2.0 weighting.
- Make the verified workflow the only path in current READMEs, articles, and
  migration examples, with separate guidance for survey researchers and AI
  agents and separate decision/statistical report views.

## [1.1.0] - 2026-07-15

### Added

- Add verified external target/reference import, outcome-blind planning, explicit
  human approval, locked-weight execution, post-lock impact assessment, dual
  report audiences, and v2 audit evidence.
- Add CSV and Excel import samples, a safe-workflow vignette, and controlled
  simulation/reference validation.

### Changed

- Deprecate subjective target and runtime-margin controls ahead of their removal
  in WFC 2.0.0.
- Require CI to run the safe-workflow validation against the suggested `survey`
  reference implementation.
- Standardize the maintainer and company contact identities.
- Re-license WFC under GPL (>= 2) and document separately distributed
  dependency copyright boundaries in `inst/COPYRIGHTS`.

## [1.0.0] - 2026-07-11

### Added

- Import the WFC R package (v1.0.0) into the WeianData organization from its
  incubation repository, including sources, tests, vignettes, benchmarks,
  design documents, and development plan archive.
- Adopt the WeianData repository template governance baseline (contribution,
  security, ownership, versioning, and CI documents).

### Changed

- Update package URLs and installation instructions to point to
  `github.com/weiandata/WFC`.

See [NEWS.md](NEWS.md) for the full feature history from 0.1.0 to 1.0.0.
