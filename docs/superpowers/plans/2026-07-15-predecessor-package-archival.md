# Predecessor Package Archival Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The user prohibited subagents and CodeGraph.

**Goal:** Retire and archive `mergecalib` and `ratecalib` after validated WFC 2.0 release, while preserving history, licensing, provenance, and an honest migration boundary.

**Architecture:** Treat archival as two focused repository changes followed by approved external administration. Each predecessor receives an immutable retirement notice, successor mapping, final verification record, and package-index disposition before it becomes read-only.

**Tech Stack:** Git, Markdown, R package metadata/build/check, official package indexes, GitHub organization controls.

## Global Constraints

- Begin only after WFC 2.0 release evidence, migration validation, accountable approval, and qualified statistical review are complete.
- No CodeGraph or subagents.
- Preserve every predecessor commit, tag, release, license, and copyright record.
- Do not create compatibility packages, delete history, or publish new functionality.
- High-risk behavior says “no replacement” and never links to a workaround.
- GitHub archival is an external lifecycle mutation requiring explicit organization-owner approval immediately before execution.
- Use company identity and one short-lived branch per repository.

---

### Task 1: Record the successor release gate

**Files:** Create in WFC `docs/validation/predecessor-archival-gate.md`.

**Interfaces:** Produces the immutable WFC evidence record consumed by both predecessor archival changes.

- [ ] **Step 1: Verify the WFC successor**

```bash
git status --short
git tag --list 'v2.0.0'
git show --no-patch --format='%H%n%an <%ae>%n%s' v2.0.0
```

Expected: clean status, exactly one `v2.0.0` tag, company identity, and reviewed
release commit. Stop if any condition fails.

- [ ] **Step 2: Verify evidence fields**

Confirm the WFC 2.0 validation report names source revision, artifact checksum,
check commands/results, limitations, migration guide, accountable approval, and
qualified human statistical review scope. Stop if a field is absent.

- [ ] **Step 3: Write and commit the gate**

Record version/tag/commit, checksum, evidence paths, approvals, and the decision
that each predecessor capability is safely covered or intentionally unsupported.

```bash
git add docs/validation/predecessor-archival-gate.md
git commit -m "docs(governance): record predecessor archival gate"
```

### Task 2: Prepare mergecalib for archival

**Files in `/Users/makunxiang/Developer/WeianData/mergecalib`:** Modify `README.md`, `DESCRIPTION`, `NEWS.md`, `CHANGELOG.md`, `SECURITY.md`; create `docs/ARCHIVED.md`.

**Interfaces:** Declares lifecycle `archived`, successor WFC >= 2.0.0, safe mappings, and no replacement for outcome-driven optimization.

- [ ] **Step 1: Create a clean archival branch and run baseline tests**

```bash
git status --short
git switch -c docs/archive-for-wfc-2
Rscript -e 'devtools::test()'
```

Expected: clean status before branch creation and zero test failures.

- [ ] **Step 2: Add the retirement boundary**

Put the retirement date, final supported version, WFC successor, security
contact, and GPL retention at the top of README and in `docs/ARCHIVED.md`. Include
this exact statement:

```text
Outcome-grade interval constraints, outcome-heterogeneity optimization, and
target-driven relaxation were intentionally not migrated and have no supported
replacement in WFC.
```

- [ ] **Step 3: Update metadata without touching R code**

Add `Lifecycle: archived` to `DESCRIPTION`; add final NEWS/CHANGELOG entries;
change SECURITY from active fixes to retained private historical reporting. Do
not modify exported functions or numerical behavior.

- [ ] **Step 4: Verify and commit**

```bash
Rscript -e 'devtools::test()'
R CMD build .
R CMD check mergecalib_0.2.0.9000.tar.gz --no-manual
```

Expected: zero errors/zero warnings; record every NOTE.

```bash
git add README.md DESCRIPTION NEWS.md CHANGELOG.md SECURITY.md docs/ARCHIVED.md
git commit -m "docs(governance): retire mergecalib in favor of WFC 2"
```

### Task 3: Prepare ratecalib for archival

**Files in `/Users/makunxiang/Developer/WeianData/ratecalib`:** Modify `README.md`, `package/DESCRIPTION`, `package/NEWS.md`, `CHANGELOG.md`, `SECURITY.md`, `DISCLAIMER.md`; create `docs/ARCHIVED.md`.

**Interfaces:** Declares lifecycle `archived`, safe successor mappings, and no replacement for study-result targeting.

- [ ] **Step 1: Create a clean archival branch and run baseline tests**

```bash
git status --short
git switch -c docs/archive-for-wfc-2
Rscript -e 'devtools::test("package")'
```

Expected: clean status before branch creation and zero test failures.

- [ ] **Step 2: Add the retirement boundary**

Put the lifecycle/support fields in README and `docs/ARCHIVED.md`. Add this exact
statement to README, disclaimer, and archival record:

```text
Calibration to user-supplied pass rates, study-result proportions, study-result
means, study-result totals, exact result targets, and prioritized result targets
was intentionally not migrated and has no supported replacement in WFC.
```

Map generic checks, bounded external-margin weighting, diagnostics, replicates,
and verified CSV/Excel import to WFC 2.0 documentation.

- [ ] **Step 3: Update metadata without touching statistical code**

Add `Lifecycle: archived` to `package/DESCRIPTION`; add final NEWS/CHANGELOG
entries; update SECURITY. Do not modify `package/R/` or publish a feature release.

- [ ] **Step 4: Verify and commit**

```bash
Rscript -e 'devtools::test("package")'
R CMD build package
R CMD check ratecalib_0.3.1.tar.gz --no-manual
```

Expected: zero errors/zero warnings; record every NOTE.

```bash
git add README.md package/DESCRIPTION package/NEWS.md CHANGELOG.md SECURITY.md DISCLAIMER.md docs/ARCHIVED.md
git commit -m "docs(governance): retire ratecalib in favor of WFC 2"
```

### Task 4: Resolve official package-index status

**Files:** Update each predecessor `docs/ARCHIVED.md` with observed status.

**Interfaces:** Produces an evidence-backed CRAN/other-index disposition rather than inferring status from local comments or tarballs.

- [ ] **Step 1: Query CRAN with approved network access**

```r
available <- rownames(available.packages(repos = "https://cloud.r-project.org"))
c(mergecalib = "mergecalib" %in% available,
  ratecalib = "ratecalib" %in% available)
```

Expected: a dated named logical result captured in the archival records.

- [ ] **Step 2: Apply the observed result**

For each `TRUE`, follow the current official CRAN maintainer/archive procedure,
retain correspondence, and record the date. For each `FALSE`, record “not listed
on CRAN on the verification date; no CRAN archival request needed.” Repeat for
every other distribution index named in repository documentation.

- [ ] **Step 3: Commit index evidence separately**

```bash
git add docs/ARCHIVED.md
git commit -m "docs(governance): record package index disposition"
```

Run and commit separately in each predecessor repository.

### Task 5: Archive both organization repositories

**Files:** No source changes after reviewed archival commits. Preserve external organization audit evidence.

**Interfaces:** Makes both repositories read-only without deleting or transferring them.

- [ ] **Step 1: Complete the final checklist**

For each repository verify: reviewed archival commit is on default branch;
required checks pass; tags/releases remain; README successor link resolves;
license/COPYRIGHTS remain; no open security issue requires a fix; index status is
recorded; WFC v2.0.0 remains available.

- [ ] **Step 2: Request explicit organization-owner approval**

Present repository names, exact commits, package-index status, successor commit,
and recovery implications. Do not perform the external mutation without approval.

- [ ] **Step 3: Archive through approved organization controls**

Archive `weiandata/mergecalib` and `weiandata/ratecalib` through GitHub settings
or an approved administrative `gh` command. Do not delete, transfer, change
visibility, rewrite history, or remove releases.

- [ ] **Step 4: Verify preserved read-only state**

Confirm Archived status, readable default branches/tags, disabled issue/PR
creation, rendered successor links, downloadable releases, and organization
audit evidence naming approver, operator, time, repositories, and commits.
