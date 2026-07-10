# WeianData Repository Template

The official language-independent starting point for repositories owned or
maintained by WeianData.

Status: Active

Owner: WeianData Engineering

## Project Overview

This repository is the golden template for new WeianData software, research,
documentation, SDK, AI, infrastructure, and static-site repositories. It
provides the common governance and documentation baseline without choosing a
programming language, framework, package manager, or deployment model.

After creating a repository from this template, replace this overview with the
new project's purpose, audience, status, owner, supported use cases, and
non-goals.

## Features

- A predictable, AI-friendly repository structure.
- Issue and pull request templates for reviewable work.
- Language-neutral Markdown and link checks.
- Contribution, security, versioning, and ownership defaults.
- Dedicated locations for documentation, examples, and utility scripts.

This template intentionally contains no business logic, source layout, test
layout, dependency manifest, dataset, container configuration, or
language-specific automation. Add only the components required by the new
project and its selected operating mode.

## Repository Structure

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/
│   ├── workflows/
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/
├── examples/
├── scripts/
├── .editorconfig
├── .gitignore
├── CHANGELOG.md
├── CODEOWNERS
├── CONTRIBUTING.md
├── LICENSE
├── README.md
└── SECURITY.md
```

Language-native source and test directories belong in the generated
repository, not in this common template.

## Getting Started

1. On GitHub, open this repository and select **Use this template**.
2. Choose **Create a new repository**.
3. Enter a lowercase, hyphen-separated repository name and select the correct
   owner and visibility.
4. Clone the generated repository and create a short-lived topic branch from
   `main`.
5. Replace all project placeholders, choose a license or proprietary notice,
   and tailor the structure to the language and operating mode.
6. Add reproducible setup, validation, security, and release automation before
   the repository is relied on.
7. Configure branch protection, required checks, and appropriate reviewers in
   GitHub.

Repository names use lowercase kebab case, for example `irt-engine` or
`knowledge-base`.

## Development

Changes use short-lived branches named `<category>/<kebab-case-topic>`, such as
`feature/add-score-export` or `docs/clarify-setup`. Submit changes through a
pull request and keep `main` releasable. See [CONTRIBUTING.md](CONTRIBUTING.md)
for commit, review, testing, and evidence requirements.

The shared workflow checks Markdown style and links. Generated repositories
must add the language-specific build, test, dependency, security, and release
checks required by their project.

## Documentation

- [Documentation index](docs/README.md)
- [Repository standard summary](docs/repository-standard.md)
- [Template development guide](docs/Repository_Template_Development_Guide.md)
- [WeianData Engineering Handbook](https://github.com/weiandata/.github/blob/main/handbook/README.md)

The Engineering Handbook is the normative source for engineering rules. This
template implements safe defaults and does not replace or redefine those
standards.

## Repository Lifecycle

Every repository moves through planning, development, testing, release,
maintenance, and eventual archival. The owner must keep purpose, status,
validation evidence, supported versions, and maintenance expectations current
throughout that lifecycle.

## Data and Security

Do not commit credentials, secrets, personal information, restricted client
data, or unapproved datasets. Use synthetic, public, or explicitly authorized
fixtures and follow [SECURITY.md](SECURITY.md) for private vulnerability
reporting.

## Support

Use the repository's issue templates for non-sensitive defects, features, and
documentation work. Report security concerns only through the private channels
listed in [SECURITY.md](SECURITY.md).

## License

The included [LICENSE](LICENSE) is intentionally a placeholder. Every generated
repository must replace it with an approved license or an explicit proprietary
notice before distribution or external reliance.
