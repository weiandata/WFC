# Repository Standard

This document summarizes the baseline implemented by the WeianData repository
template. The
[Engineering Handbook](https://github.com/weiandata/.github/blob/main/handbook/README.md)
is normative and takes precedence; this summary does not redefine its rules.

## Naming

- Repository names use lowercase words separated by hyphens.
- `main` is the preferred permanent default branch.
- Short-lived topic branches use `<category>/<kebab-case-topic>`.
- Files and directories use clear, predictable, purpose-specific names.

## Documentation

- The root README states purpose, audience, status, owner, supported use,
  non-goals, setup, validation, security boundaries, support, and license.
- Detailed and durable documentation belongs in `docs/`.
- Safe examples belong in `examples/`; utility scripts belong in `scripts/`.
- Documentation changes accompany behavior, setup, interface, and policy
  changes.
- Policy is linked to its handbook owner instead of duplicated locally.

## Workflow

- Plan one bounded outcome and track it in an issue when appropriate.
- Develop on a short-lived branch from an up-to-date `main`.
- Add deterministic tests and reproducible validation for executable behavior.
- Submit a focused pull request with evidence, risk, rollback, release impact,
  and material AI-assistance disclosure.
- Pass required checks and reviews before integration.
- Keep `main` protected and releasable.

## Versioning

- Stable released artifacts use Semantic Versioning: `MAJOR.MINOR.PATCH`.
- Release tags use a leading `v`, for example `v1.2.3`, and identify immutable
  source revisions.
- Breaking changes include migration guidance and explicit compatibility impact.
- User-visible and scientifically meaningful changes are recorded in
  `CHANGELOG.md` using Keep a Changelog sections.

## Security

- Never commit secrets, credentials, restricted client data, personal
  information, or embargoed vulnerabilities.
- Use synthetic, public, or explicitly authorized test and example data.
- Report vulnerabilities through the private channel in `SECURITY.md`.
- Apply least privilege, supported dependencies, risk-appropriate review, and
  required security checks.
- Select an approved license or explicit proprietary notice before distribution
  or external reliance.

## Lifecycle

Repositories progress through planning, development, testing, release,
maintenance, and archival. The repository owner keeps ownership, purpose,
status, supported versions, documentation, evidence, and access controls current
at every stage.
