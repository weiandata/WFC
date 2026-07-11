# WFC — Design Document, Extension 3

**Audience repositioning, guided workflow, and the 0.10 → 1.0 roadmap**

Companion to `weightflow_design.md` (core, 0.1), `weightflow_poststrat_design.md` (Extension 1), and `weightflow_roadmap_design.md` (Extension 2). Those documents were written under the package's original name `weightflow`; the package was renamed **WFC** at 0.9.0 after a CRAN name collision. All architectural commitments in the earlier documents remain in force; this document extends them, it does not revise them.

This extension does two things. First, it repositions the package around its actual future audience. Second, it commits the release sequence from 0.10 through 1.0, absorbing the items Extension 2 deferred (`wf_auto_trim()`, `wf_suggest_ladder()`, `wf_report()`, parallel execution) and adding six new directions agreed in project review: usability layers, ecosystem interoperability, production pipeline infrastructure, a widened method family, deeper diagnostics, and publication infrastructure.

---

## 1. Repositioning: the non-specialist survey manager

The core documents implicitly assume a user who knows what raking, margins, and design effects are. The package's future primary audience is different: **survey managers and field-operations staff who are responsible for producing weighted results but are not statisticians**. They can run a few lines of R from a template, or use a point-and-click interface; they cannot debug a `wf_error_feasibility` from first principles.

This repositioning adds three design principles to the original P1–P6. None of them weakens the originals — in particular P1 (discipline over convenience) is preserved by construction, as §4 explains.

**P7 — Explain, don't just report.** Every automated decision and every refusal must be expressible in plain language that states *what happened, why, and what to do next*, at a level a non-statistician can act on. The classed-condition system (P5) already carries the machine-readable payload; P7 adds the human-readable rendering layer on top of it.

**P8 — One engine, two paths.** The guided path (`wf_autoweigh()`, WFCstudio) is a thin orchestration over the exact same constructors, prechecks, engines, and diagnostics the expert path uses. It never forks the computation, never relaxes a check, and every automated choice it makes is the same reviewable artifact (`wf_collapse_plan`, trim recommendation, ladder draft) an expert would produce by hand. Guided mode is a driver, not a dialect.

**P9 — Localized outputs, English internals.** Code, comments, tests, and R documentation remain English-only (the existing language policy). Human-facing *outputs* — reports, verdict lines, GUI labels — are localizable, shipping with English and Simplified Chinese resource bundles, defaulting to the session locale and switchable via a `lang` argument or `options(wfc.lang = ...)`.

---

## 2. Roadmap at a glance

| Release | Theme | Headline API |
|---|---|---|
| 0.10 | Usability foundations | `wf_report()`, `plot()` methods, `wf_auto_trim()`, `wf_suggest_ladder()` |
| 0.11 | Guided workflow | `wf_autoweigh()`, output localization (`lang`, `wfc.lang`) |
| 0.12 | Ecosystem interoperability | `as_svydesign()`, `as_svrepdesign()`, `tidy()`/`glance()`/`augment()`; WFCstudio sibling package kickoff |
| 0.13 | Production infrastructure | `wf_pipeline()`, `wf_run()`, `wf_validate()`, `wf_audit_export()` |
| 0.14 | Methods I | `wf_calibrate(method = "soft")` (priority), `method = "ebal"` |
| 0.15 | Methods II + diagnostics | `wf_attrition()`, k-source `wf_blend()`, `wf_influence()`, sensitivity bounds |
| 0.16 | Performance engineering | `parallel = TRUE`, progress reporting, optional Rcpp kernel |
| 1.0 | Freeze and publish | API freeze, CRAN submission, bilingual pkgdown site, WFCstudio beta |

Items retained from Extension 2 and not listed above keep their original designs and land opportunistically: MRP (`method = "mrp"`, `redistribute = "model"`) after 1.0; `rf`/`gbm` propensity backends and `kernel`/`matching` weights when a production need arises; Fay's BRR alongside 0.15's variance work.

---

## 3. Release 0.10 — Usability foundations

### 3.1 `wf_report()` — the weighting dossier, re-aimed

Extension 2 §5.4 specified `wf_report()` as a methods-appendix generator. It is re-aimed at two audiences via one argument:

```r
wf_report(w, target = NULL, audience = c("manager", "analyst"),
          lang = NULL, output = c("object", "html", "markdown"), file = NULL)
```

`audience = "analyst"` renders the Extension 2 dossier (deff, ESS, residuals, λ sensitivity, balance/overlap). `audience = "manager"` renders a decision-oriented summary: a traffic-light quality verdict per group, which groups are publishable separately and which only in aggregate, what was merged or trimmed and why, in plain language (P7). Both renderings read the same underlying structured object; the manager view is a projection, not a separate computation. `output = "html"` uses only base tooling (no rmarkdown hard dependency; an enhanced theme may use rmarkdown behind `Suggests:`).

### 3.2 `plot()` methods

Base-graphics methods, zero new dependencies: `plot(wf_weights)` (per-group weight distributions with trim bounds), `plot(wf_diagnostics)` (deff/ESS dot chart), `plot(wf_blend_result)` (λ sensitivity curve), `plot(wf_propensity result)` (overlap densities and a balance love plot).

### 3.3 `wf_auto_trim()` and `wf_suggest_ladder()`

Implemented exactly as designed in Extension 2 §5.2–5.3 (bias–variance frontier sweep; information-loss-ordered ladder drafting). Their positioning changes: they are no longer optional conveniences but the machinery `wf_autoweigh()` (0.11) relies on to propose defensible defaults. They therefore land one release before it.

---

## 4. Release 0.11 — Guided workflow

### 4.1 `wf_autoweigh()`

One call that walks the full discipline loop and narrates it:

```r
res <- wf_autoweigh(
  sample, population,                 # or a ready wf_target
  dims,                               # wf_dims; ladders strongly recommended
  by = NULL, id = NULL,
  method = c("auto", "raking", "poststrat", "logit"),
  interactive = base::interactive(),  # ask before applying remediations
  lang = NULL
)
```

Internally: build target (if given raw population data) → `wf_precheck()` → if blocked, generate remediation proposals via `wf_suggest_collapse()` / `wf_suggest_ladder()` and either ask (interactive) or apply-and-log (non-interactive, only remediations that are *pre-declared* ladders — never invented merges, per Extension 1 §4) → re-precheck → calibrate → `wf_auto_trim()` recommendation → `wf_diagnose()` → `wf_report(audience = "manager")`.

The return value is a `wf_autoweigh_result`: the `wf_weights`, the report, and a **decision ledger** — an ordered record of every automated choice (what, why, which reviewable artifact) so an expert can audit or veto after the fact.

**P1 is preserved by construction.** `wf_autoweigh()` has no power the expert path lacks: it cannot bypass a blocking precheck; when no pre-declared ladder can resolve an infeasibility it stops and explains, in plain language, exactly which category in which group is infeasible and what a ladder that would fix it looks like. Guided mode automates the *proposal* loop, never the *approval* of anything that was not declared in advance.

### 4.2 Output localization

A small internal i18n layer: message catalogs under `inst/i18n/` (`en.dcf`, `zh_CN.dcf`), an internal `.wf_tr(key, ...)` lookup with `sprintf`-style interpolation, resolution order `lang` argument → `options(wfc.lang)` → session locale → English fallback. Scope: report text, verdict lines, `wf_autoweigh()` narration, plot labels. Explicitly out of scope: error/warning `message` fields, R documentation, and code (English-only policy unchanged); classed conditions remain the stable machine interface so localization can never break programmatic handling.

---

## 5. Release 0.12 — Ecosystem interoperability

### 5.1 survey / srvyr bridges

```r
as_svydesign(w, data, ...)            # wf_weights  -> survey::svydesign
as_svrepdesign(r, data, ...)          # wf_replicate_weights -> survey::svrepdesign
```

`as_svrepdesign()` maps the stored `(scale, rscales, method)` onto the corresponding `svrepdesign` types (bootstrap / JK1-JKn / BRR), so downstream `svymean`, `svyglm`, and contingency tables carry WFC's replication-based uncertainty unchanged. Both live behind `Suggests: survey` with a classed error naming the missing package. This closes the largest gap for adoption: today weights exit the package as a bare data frame.

### 5.2 broom-style tidiers

`tidy()`, `glance()`, `augment()` methods for `wf_weights`, `wf_diagnostics`, `wf_blend_result`, and `wf_variance_result` (registered conditionally on `generics`/`broom`). `augment()` joins weights back onto the input sample by id — the single most-asked-for convenience in practice.

### 5.3 WFCstudio kickoff (sibling package)

The GUI is a **separate package**, `WFCstudio`, so the core keeps its zero-hard-dependency promise. Scope for the initial beta: upload sample and population files (csv/xlsx) → map columns to dims/by/count interactively → run `wf_autoweigh()` → view the manager report → download weights and the report. The UI layer contains *no statistics*: it renders WFC's structured objects and classed conditions (the programmatic reaction path P5 anticipated). Bilingual UI via the same i18n catalogs. Development starts at 0.12; beta ships with 1.0.

---

## 6. Release 0.13 — Production pipeline infrastructure

### 6.1 `wf_pipeline()` and `wf_run()`

A declarative, serializable specification of a full weighting chain:

```r
spec <- wf_pipeline(
  target   = list(mode = "population", key_map = ..., count = "pop", by = "prov"),
  stages   = list(
    propensity = list(formula = member ~ age + edu),
    calibrate  = list(method = "logit", bounds = c(0.3, 3))
  ),
  validate = list(max_deff = 6, max_margin_dev = 1e-4)
)
wf_run(spec, sample, population, reference = NULL)
```

The spec is a plain list (JSON/YAML-serializable, hashable into provenance), so a production round is reproducible from a versioned text artifact. `wf_run()` is also the natural `refit` closure for `wf_replicates()`, replacing hand-written closures with a declared object.

### 6.2 `wf_validate()` — weight drift detection

Compares a new `wf_weights` against a reference release: per-group deff and ESS deltas, margin-deviation deltas, distributional shift of weight ratios (per-id where ids match), group coverage changes. Thresholds are declared, violations raise `wf_warning_quality` / `wf_error_input` with structured payloads, and the comparison table feeds `wf_report()`. This is the "did this quarter's weights silently change character" check every recurring survey needs.

### 6.3 `wf_audit_export()`

Serializes any result's provenance (including composed stages and the decision ledger) to a self-contained JSON audit file with input hashes, package version, settings, seeds, and timestamps — the machine-readable counterpart of `wf_report()`.

---

## 7. Release 0.14 — Methods I: soft calibration and entropy balancing (Seam 2)

### 7.1 `wf_calibrate(method = "soft")` — priority item

Hard calibration treats every margin as an exact constraint; when a category is infeasible or barely supported the current answer is "collapse or stop". Soft (penalized/ridge) calibration replaces exact constraints with a penalized objective — margins are met approximately, with per-margin tolerances or costs:

```r
wf_calibrate(sample, target, method = "soft",
             tolerance = 0.02,            # scalar or per-dimension named vector
             bounds = NULL, init_weight = NULL, ...)
```

Design intent for the non-specialist audience: many "infeasible target" situations that today require understanding and authoring collapse ladders become a *declared tolerance* instead. Discipline is preserved: the achieved-vs-target gap per margin is always computed, reported, and bounded by the declared tolerance — `wf_precheck()` gains a mode that classifies `cat_infeasible` as soft-resolvable when `method = "soft"` is requested, and the report states exactly which margins were relaxed and by how much. Implementation is a penalized variant of the 0.8 Newton solver (same constraint builder, augmented objective), so it inherits the existing engine tests.

### 7.2 `wf_calibrate(method = "ebal")`

Entropy balancing (Hainmueller 2012): exact first-moment balance with minimum Kullback–Leibler divergence from base weights. Fits the existing Seam 2 signature and `wf_target` contract; useful when weight-variance minimization is the binding concern.

---

## 8. Release 0.15 — Methods II and deeper diagnostics

- **`wf_attrition()`** — panel/wave nonresponse: models retention between waves (base-R `glm`, same discipline as `wf_propensity()`: overlap + balance diagnostics), emits a stage-1 `wf_weights` that chains through `wf_compose()` across waves. Wave-to-wave weight stability enters `wf_validate()`.
- **k-source `wf_blend()`** — generalize from two sources to a named list, with λ vectors per cell (neff / inverse-variance shares across k sources; fixed λ as a simplex-constrained table). The two-source API remains sugar.
- **`wf_influence()`** — per-unit leverage on the calibrated solution (weight ratio, contribution to margin fit, deff contribution), flagging the handful of respondents that drive extreme weights — the practical question behind most trimming debates.
- **Sensitivity bounds** — for propensity-corrected estimates, report how strong an unmeasured selection factor would need to be to overturn a conclusion (Rosenbaum-style bounds on Seam 2's propensity output), continuing the "assumptions surfaced, not hidden" commitment.
- Fay's BRR (`rho`) lands here with the variance work retained from Extension 2.

---

## 9. Release 0.16 — Performance engineering

- `parallel = TRUE` on `wf_rake()` / `wf_poststrat()` / `wf_replicates()` via `parallel::mclapply` (base R; Windows falls back to serial with a note), with per-group determinism guaranteeing identical results — exactly as reserved in core §11.
- Progress reporting for long runs (replicates, autoweigh over many groups) via `cli` behind `Suggests:`, silent fallback otherwise.
- The Rcpp IPF kernel remains an escape hatch, built **only if** 0.16 profiling on national-scale data shows the R kernel binding; the decision and benchmark enter this document as an addendum at that time.

---

## 10. Release 1.0 — Freeze and publish

- **API freeze.** All exported signatures, S3 class fields, and condition classes frozen; additions allowed, removals and semantic changes require a major version. A deprecation policy (one full minor release with classed `wf_warning_deprecated`) is documented.
- **CRAN submission.** `cran-comments.md`, reverse-dependency-free initial submission, win-builder/mac-builder pre-checks, the existing five-platform CI as gate.
- **Bilingual pkgdown site.** English reference (auto-generated) plus hand-written articles in English and Simplified Chinese: quick start, the precheck→execute→diagnose discipline, bringing your own population data, dirty-data handling, and a manager-oriented "reading the weighting report" guide. Chinese articles live on the site, not in the package, keeping the language policy intact.
- **WFCstudio beta** released alongside, pinned to the frozen 1.0 API.
- The three vignettes promised in core §13 ship as part of this cycle (they double as site articles).

---

## 11. Cross-cutting commitments (extended)

Everything in Extension 2 §7 continues to hold. Additions:

- **Zero-hard-dependency core, forever.** survey, srvyr, broom/generics, cli, rmarkdown, shiny: all behind `Suggests:` or in the WFCstudio sibling. The computational core stays base-R installable.
- **Guided mode is auditable mode.** Anything `wf_autoweigh()` or WFCstudio decides automatically exists as a reviewable artifact in the decision ledger; there is no automated action without a corresponding inspectable object.
- **Localization never touches semantics.** Message catalogs affect rendering only; condition classes and payloads are the stable contract.
- **Every methods addition ships with its own diagnostics** (soft-calibration relaxation report, ebal divergence, attrition balance, influence tables) — the precheck→execute→diagnose loop closes for each new method before it is exported.

---

## 12. Consolidated public API after 1.0 (planned)

```
# guided path (0.11)
wf_autoweigh()

# reporting & visualization (0.10)
wf_report(); plot() methods; wf_auto_trim(); wf_suggest_ladder()

# interoperability (0.12)
as_svydesign(); as_svrepdesign(); tidy(); glance(); augment()

# production infrastructure (0.13)
wf_pipeline(); wf_run(); wf_validate(); wf_audit_export()

# methods (0.14 / 0.15)
wf_calibrate(method = "soft" | "ebal" | ...); wf_attrition()
wf_blend(<k sources>); wf_influence()

# performance (0.16)
parallel = TRUE; progress reporting

# sibling package
WFCstudio (GUI over the same engine)
```

Each release is independently shippable; the ordering encodes the agreed priority — make the guided path real first, connect to the ecosystem second, harden production third, then widen the method family — and the seams guarantee any reordering remains safe.

---

Reference implementations of the above live in `inst/reference/`, following the convention of the earlier extensions: `wfc_future_usability.R` (§3–§4: i18n, auto-trim, ladder drafting, report, autoweigh, plots), `wfc_future_infrastructure.R` (§5–§6: survey bridges, tidiers, pipeline, validate, audit export), and `wfc_future_methods.R` (§7–§8: soft calibration, entropy balancing, attrition weighting, influence diagnostics). They are prototypes to be sourced after `library(WFC)`, not installed API.
