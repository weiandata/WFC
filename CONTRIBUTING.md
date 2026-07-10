# Contributing

Thank you for improving this repository. Contributions must follow the
[WeianData Engineering Handbook](https://github.com/weiandata/.github/blob/main/handbook/README.md),
which remains the normative source when this guide is incomplete or changes.

Do not include credentials, personal information, restricted client data,
embargoed vulnerabilities, or material that WeianData does not have the right
to use.

## Branch Workflow

1. Start from an up-to-date, protected `main` branch.
2. Create one short-lived branch for one bounded outcome.
3. Name it `<category>/<kebab-case-topic>` using `feature`, `fix`, `docs`,
   `refactor`, `test`, `release`, or `hotfix`.
4. Open a draft pull request early when the change is risky or needs alignment.
5. Keep the branch current, pass required checks, obtain required reviews, and
   delete the branch after integration.

Examples include `feature/add-export`, `fix/empty-input-guard`, and
`docs/update-quick-start`.

## Commit Messages

Use this form:

```text
<type>(<optional-scope>): <imperative summary>

<optional body explaining why and important consequences>

<optional trailers>
```

Allowed types are `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`,
`ci`, `chore`, and `revert`. Keep the summary concise, start it with lowercase
after the colon, omit a final period, and add a `BREAKING CHANGE:` footer when
required.

Example:

```text
docs(readme): clarify repository setup
```

## Pull Requests

Use the pull request template and provide enough evidence for another person to
review the outcome, risk, and recovery path. A pull request should:

- link its issue or explain why none is needed;
- describe the change and explicit non-changes;
- include commands and primary verification evidence;
- classify statistical, security, client-data, compatibility, and operational
  risk where relevant;
- document migration, rollback, documentation, and release impact;
- disclose material AI assistance and how a human verified the output; and
- request the domain reviewers required by the change.

Keep the diff focused. Required checks must pass, and review findings must be
resolved before integration. Use the repository's documented merge method
consistently.

## Code Review

Reviewers evaluate correctness, clarity, maintainability, reproducibility,
security, privacy, compatibility, and evidence. Statistical, scientific,
security, dependency, license, client-data, or domain-impacting changes require
an appropriately qualified reviewer.

Approval does not replace automated checks. Re-run validation after material
review changes, and do not rely on self-approval alone for Controlled work.

## Documentation and Testing

Update documentation in the same change as behavior, setup, or interface
changes. Add or update deterministic tests whenever executable behavior exists.
Use only synthetic, public, or explicitly authorized data in tests and examples.

The template workflow validates Markdown and links. Each generated repository
must document and automate its language-specific setup and validation commands.
