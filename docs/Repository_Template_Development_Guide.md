# WeianData Repository Template Development Guide

Version: 1.0

Status: Approved

Owner: WeianData

---

# Objective

This document defines the complete development requirements for the WeianData `repository-template`.

The goal is to transform the current minimal repository into the official engineering template used by every future repository under the WeianData GitHub Organization.

This repository is **NOT** an example project.

It is the Golden Repository that defines the engineering baseline for all software, research, documentation, SDK, AI, and infrastructure repositories.

Every future repository should be generated from this template.

---

# Relationship to Engineering Handbook

This repository must fully comply with the WeianData Engineering Handbook.

The handbook defines engineering rules.

The repository template implements those rules.

The template must never redefine handbook standards.

Instead, it should reference the handbook whenever possible.

---

# Development Goals

The completed repository template should satisfy the following goals.

- Professional
- Minimal
- Scalable
- AI-friendly
- Human-friendly
- Language-independent
- Future-proof

It should support repositories written in:

- Python
- R
- Rust
- JavaScript
- TypeScript
- Documentation only
- Static websites

without requiring structural redesign.

---

# Repository Standard v1.0

## 1. Repository Purpose

Every repository generated from this template must:

- have a clear purpose
- contain reproducible engineering practices
- be understandable by new engineers
- be understandable by AI coding assistants

---

## 2. Repository Naming

Repository names must:

- use lowercase
- use hyphen-separated words

Examples

```
irt-engine
irt-assistant
repository-template
knowledge-base
```

Forbidden

```
MyProject
IRTEngine
project-final
```

---

## 3. Default Branch

```
main
```

Only one permanent branch is required.

Feature branches may be added later.

---

## 4. Mandatory Files

Every repository must contain:

```
README.md
LICENSE
CHANGELOG.md
.editorconfig
.gitignore
```

---

## 5. Optional Directories

The template should create only language-independent directories.

```
.github/
docs/
examples/
scripts/
```

Do NOT create

```
src/
tests/
```

These depend on programming language.

---

## 6. README Standard

Every generated repository should contain a README with sections similar to:

```
Project Overview

Features

Repository Structure

Getting Started

Development

Documentation

License
```

---

## 7. GitHub Directory

The repository should contain

```
.github/

ISSUE_TEMPLATE/

workflows/

PULL_REQUEST_TEMPLATE.md
```

---

## 8. Documentation

Documentation belongs in

```
docs/
```

Examples belong in

```
examples/
```

Utility scripts belong in

```
scripts/
```

---

## 9. CHANGELOG

Use Keep a Changelog format.

Semantic Versioning.

---

## 10. License

Leave the LICENSE placeholder.

Individual repositories decide the final license.

---

## 11. Git Ignore

Do not assume language.

The template should provide a minimal universal gitignore.

Ignore:

```
.DS_Store
Thumbs.db
.vscode/
.idea/
.env
```

Language-specific ignores belong to each repository.

---

## 12. AI Compatibility

The repository should be optimized for AI.

Requirements

- predictable structure
- descriptive filenames
- minimal ambiguity
- documentation before implementation

---

# Repository Structure

The completed template should look like

repository-template

```
.github/

ISSUE_TEMPLATE/

workflows/

PULL_REQUEST_TEMPLATE.md

docs/

README.md

examples/

README.md

scripts/

README.md

README.md

CHANGELOG.md

LICENSE

.editorconfig

.gitignore
```

---

# README Requirements

The root README should explain

- purpose
- usage
- how to generate repositories
- relationship to handbook
- repository lifecycle

---

# docs/

Create

```
docs/

README.md

repository-standard.md
```

The repository standard should summarize:

- naming
- documentation
- workflow
- versioning
- security

---

# examples/

Should explain

```
Example code

Example dataset

Example notebook

Example workflow
```

No actual examples required.

---

# scripts/

Should explain

Utility scripts only.

No business logic.

---

# GitHub Templates

Create

```
ISSUE_TEMPLATE

bug.md

feature.md

documentation.md
```

Each template should contain

- summary
- expected behavior
- checklist

---

Create

```
PULL_REQUEST_TEMPLATE.md
```

Include

```
Description

Related Issue

Testing

Checklist
```

---

# GitHub Actions

Create placeholder workflow

```
.github/workflows/

ci.yml
```

The workflow should

- checkout repository

- verify markdown

- verify links

Future language-specific CI should be added by each repository.

---

# CODEOWNERS

Generate

```
CODEOWNERS
```

Default

```
* @makunxiang-weiandata
```

---

# SECURITY.md

Include

- reporting vulnerabilities
- supported versions
- responsible disclosure

---

# CONTRIBUTING.md

Describe

- branch workflow
- commit messages
- pull requests
- code review

Reference the Engineering Handbook.

---

# Repository Lifecycle

Every repository follows

Planning

↓

Development

↓

Testing

↓

Release

↓

Maintenance

↓

Archived

---

# Engineering Quality Requirements

Every generated repository must satisfy

Consistency

Maintainability

Reproducibility

Scalability

Readability

AI-readability

---

# Forbidden

The template must NOT

- include business code

- include language-specific frameworks

- include Docker

- include package managers

- include CI for one language only

- include datasets

- include client information

---

# Deliverables

Codex should generate

- all directory structure

- placeholder documents

- complete README

- GitHub templates

- CI placeholder

- documentation placeholders

- repository standard

- contribution guide

- security policy

without introducing unnecessary complexity.

The final repository should be immediately usable as the official template for every WeianData engineering repository.