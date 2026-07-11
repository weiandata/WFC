# weightflow — Design Document

**A survey-weighting workflow package for multi-source national surveys**

Working name: `weightflow` (verify availability on CRAN/GitHub before release; alternatives: `svycalib`, `weftr`). Version target for this document: 0.1.0. License recommendation: MIT + file LICENSE (permissive, maximizes adoption by collaborating institutions).

---

## 1. Scope and positioning

The package does **not** aim to be "another raking package". Its value proposition is the *workflow around* calibration for large national surveys with mixed probability (offline) and non-probability (online) components:

1. Schema-agnostic ingestion of sample data and population benchmarks.
2. A mandatory **precheck → execute → diagnose** discipline, so that infeasible or fragile calibration problems are detected *before* iteration, not after 200 silent sweeps.
3. Two interchangeable target-construction modes: benchmarks derived from a **reference sample's design weights** (feature values), or from **external population data** in arbitrary formats.
4. Production-grade handling of dirty inputs: missing categories, NA demographics, anomalous feature values, unmatched keys.
5. A stable core on which future weighting functionality (post-stratification, propensity adjustment, composite weighting of online+offline, replicate-weight variance estimation) can be added without breaking the API.

The IPF engine itself is a commodity; correctness is validated against `survey::rake()` in the test suite. Everything else in this document is where the package earns its existence.

---

## 2. Design principles

**P1 — Discipline over convenience.** `wf_rake()` refuses to run when the precheck reports blocking issues. There is no `force = TRUE` escape hatch on errors; the user must either fix the data or explicitly apply a documented remediation (e.g., a collapse plan). Warnings do not block but are always recorded in the result's provenance.

**P2 — Schema agnosticism.** No demographic variable name, category coding, number of dimensions, or grouping variable is hard-coded anywhere. The current project's `gender/cx/age5/edu5` by `province` is just one instantiation of a generic *dimension specification*. Adding, removing, or entirely replacing the classification system requires zero package changes.

**P3 — Canonical internal representations.** All external formats (a county-level joint population table, a reference sample with feature values, a hand-typed margins table) are converted at the boundary into one canonical `wf_target` object. The engine never sees raw external data. This is the single most important extensibility decision: every future data source only needs a new constructor, and every future engine only needs to consume `wf_target`.

**P4 — Immutability and provenance.** Functions never modify inputs in place. Every result object carries a `provenance` record: input hashes, settings, package version, timestamps, precheck summary, convergence log, trimming actions. A weighting result must be reproducible and auditable from its own metadata.

**P5 — Fail loudly, fail early, fail structurally.** All errors and warnings are classed conditions carrying machine-readable data (which group, which dimension, which categories), so that calling code — including future GUI or pipeline layers — can programmatically react instead of parsing message strings.

**P6 — Base-R core.** The computational core has zero hard dependencies (`Imports:` is empty in 0.1). Optional acceleration and tidy interfaces live behind `Suggests:`. This keeps installation trivial in restricted/intranet environments and minimizes long-term maintenance risk.

---

## 3. Data model (S3 classes)

| Class | Constructor(s) | Role |
|---|---|---|
| `wf_dims` | `wf_dims()` | Declares calibration dimensions: variable names, optional expected levels, optional collapse ladders. |
| `wf_target` | `wf_target_population()`, `wf_target_reference()`, `wf_target_manual()` | Canonical benchmark: per-group totals + per-dimension margins. Carries its `mode` ("population" / "reference" / "manual"). |
| `wf_precheck` | `wf_precheck()` | Structured issue list (data.frame) + overall verdict + suggested remediations (e.g., collapse plans). |
| `wf_weights` | returned by `wf_rake()` | Per-unit weights and feature values, per-group convergence records, full provenance. |
| `wf_diagnostics` | `wf_diagnose()` | Per-group quality table (deff, ESS, extremes, residual margin error, trim share) with print/summary methods. |
| `wf_collapse_plan` | `wf_suggest_collapse()` / user-built | An explicit, reviewable category-merge specification applied by `wf_apply_collapse()`. |

The canonical `wf_target` structure:

```r
structure(list(
  mode   = "population",           # or "reference", "manual"
  by     = "prov",                 # grouping variable name (NULL = single group)
  dims   = c("gender","cx","age5","edu5"),
  groups = list(                   # one element per group value
    `11` = list(
      total   = 18300000,          # weight-sum target for the group
      margins = list(              # named numeric vectors; names are category keys (character)
        gender = c(`1` = 9.3e6, `2` = 9.0e6),
        cx     = c(`1` = 1.6e7, `2` = 2.3e6),
        age5   = c(...), edu5 = c(...)
      )
    ),
    ...
  ),
  meta = list(source_hash = "...", created = ..., scale = "population")
), class = "wf_target")
```

Invariant enforced at construction: within each group, `sum(margins[[d]]) == total` for every dimension `d` (tolerance 1e-8 relative). This invariant is what guarantees IPF preserves the group total at every sweep.

Category keys are **always characters**. All joins between sample and target happen on `as.character()` values — this is the "keys are the only link" contract (requirement 3): the population file may have any column names and any auxiliary columns; the constructor's `key_map` argument declares which of its columns correspond to which sample variables, and values are matched as character keys.

---

## 4. Input handling: missing and anomalous data (requirement 1)

### 4.1 Taxonomy of dirt, and the assigned behavior

| Problem | Where | Default behavior | Override |
|---|---|---|---|
| NA in a calibration dimension | sample | **fractional allocation** (see 4.2) | `na = "drop"`, `na = "error"` |
| NA in the grouping variable | sample | error (`wf_error_input`) — a unit that belongs to no group cannot be calibrated | `na_group = "drop"` with warning |
| NA / NaN / Inf / `<= 0` feature value | reference sample | error listing offending row indices | `feature_na = "drop"` (drops from *target construction only*, with a warning quantifying dropped weight share) |
| Feature value > 1 | reference sample | warning (inclusion probabilities should lie in (0,1]; values > 1 suggest the column is a weight, not its reciprocal) | `feature_gt1 = "allow"` |
| Sample category absent from target | sample vs target | error: cannot assign a benchmark share | collapse plan, or `unknown = "drop"` |
| Target-positive category with zero sample support | target vs sample | error: **infeasible** — IPF cannot manufacture respondents | collapse plan (the only correct fix) |
| Duplicate unit IDs | sample | error | — |
| Zero/negative population counts | population file | zero allowed (category simply drops out of margins after aggregation); negative is an error | — |
| Group present in sample but not in target (or vice versa) | both | error, with the full list of unmatched group keys | `groups = "intersect"` restricts to common groups, with warning |
| Type instability (factor vs integer vs character coding of the same variable) | everywhere | silently harmonized: everything is compared as trimmed character keys | — |

Rows with NAs in more than `max_na_dims` dimensions (default 2) are rejected: fractional expansion across k missing 5-level dimensions multiplies the row 5^k times and, more importantly, such a unit carries almost no calibrating information.

### 4.2 Fractional allocation of NA rows

A unit with NA on dimension *d* is expanded into one pseudo-row per category of *d* (Cartesian across all its missing dimensions). Initial allocation shares are proportional to the group's target shares for the missing categories. The pseudo-rows then participate in IPF as ordinary rows; the iteration itself pulls the allocation toward consistency with all margins simultaneously (this is a one-shot EM analogue and is fully deterministic). After convergence the pseudo-rows are summed back by unit ID, so each physical respondent receives exactly one weight, and the group total is untouched.

Trimming interacts with expansion at the **person** level: caps apply to the summed per-person weight; when a cap binds, all of that person's pseudo-rows are scaled by a common factor before re-raking (see 7).

---

## 5. Dimension abstraction (requirement 2)

`wf_dims()` is the single place the classification system is declared:

```r
dims <- wf_dims(
  gender = NULL,                        # levels inferred from target
  cx     = NULL,
  age5   = c("1","2","3","4","5"),      # or declared explicitly
  edu5   = c("1","2","3","4","5"),
  .collapse = list(                     # optional pre-registered ladders
    edu5 = list(step1 = c(`1`="12", `2`="12", `3`="3", `4`="45", `5`="45")),
    age5 = list(step1 = c(`4`="45", `5`="45"))
  )
)
```

Swapping to an entirely different classification set (say `region/income4/occupation7`) means writing a different `wf_dims()` call — nothing else changes. Dimensions can be added or removed freely; the engine iterates over whatever `dims` contains. Interaction calibration is expressed *within the same abstraction*: to calibrate a two-way joint, the user (or a provided helper `wf_cross(sample, "cx", "edu5")`) creates a concatenated key variable and lists it as one more dimension. No special engine path is required.

Collapse ladders are **pre-registered, named, and explicit**. `wf_suggest_collapse()` may propose applying a ladder step for a specific group and dimension; `wf_apply_collapse()` applies it to *both* the sample and the target consistently and records the action in provenance. The engine never merges categories on its own — remediation is always a visible, user-approved step (P1).

---

## 6. Target construction: the two modes (requirements 3 & 4)

### 6.1 Mode "population" — external benchmark, arbitrary format

```r
tgt <- wf_target_population(
  pop        = county_table,                          # any data.frame
  key_map    = c(gender = "gender2", cx = "cx2",      # sample var -> pop column
                 age5 = "age5", edu5 = "edu5"),
  count      = "pop",                                 # column of population counts
  by         = "prov",
  by_key     = function(df) substr(as.character(df$unicode), 1, 2),  # or a column name
  dims       = dims,
  scale      = c("population","sample","custom"),     # weight-sum semantics
  totals     = NULL                                   # required when scale = "custom"
)
```

The constructor aggregates the file to per-group margins, validates the additivity invariant, and normalizes totals according to `scale`: `"population"` keeps true head counts (weights read as "persons represented"); `"sample"` rescales each group's total to that group's sample size (mean weight 1; requires the sample at construction or later via `wf_rescale()`); `"custom"` uses user-supplied totals. Only the mapped key columns and the count column are ever read — every other column in the population file is ignored, which is what makes the format-agnostic contract cheap to honor.

If the file is *already* a margins table (one row per group × dimension × category) rather than a joint table, `wf_target_manual()` accepts it directly with a `dim_col`/`cat_col`/`value_col` mapping.

### 6.2 Mode "reference" — benchmark from a weighted reference sample

```r
tgt <- wf_target_reference(
  ref     = offline_sample,     # data.frame containing feature values
  feature = "ps",               # feature value = 1/design weight (inclusion prob.)
  dims    = dims,
  by      = "prov"
)
```

Weights are recovered as `1/feature` after the anomaly screen of 4.1; per-group weighted margins and totals become the target. The resulting `wf_target` is structurally identical to the population mode, so `wf_precheck()`, `wf_rake()`, and `wf_diagnose()` are completely mode-blind — the two computation paths the requirements demand are two constructors, not two engines. Both modes can also be **blended**: `wf_target_shrink(tgt_group, tgt_national, lambda)` implements small-group shrinkage toward a national target, for sparse-province situations.

---

## 7. Execution: `wf_rake()`

```r
w <- wf_rake(
  sample, target,
  id          = "resp_id",          # NULL -> row numbers
  na          = c("fractional","drop","error"),
  trim        = c(lo = 0.05, hi = 8), trim_cycles = 4,   # NULL disables
  tol         = 1e-6, max_iter = 200,
  precheck    = TRUE,               # runs wf_precheck(); aborts on blocking issues
  keep_rows   = FALSE               # TRUE retains the expanded pseudo-row table
)
```

Per group, the engine: (1) resolves category keys to integer level indices once (`match()`), so the iteration touches no strings; (2) performs fractional expansion; (3) runs vectorized IPF sweeps — for each dimension, level-wise weighted sums via `rowsum()` on the integer index, ratio update `w <- w * ratio[idx]`, O(n) per dimension with no per-category inner loop; (4) declares convergence when the largest |ratio − 1| in a full sweep falls below `tol`; (5) applies person-level trimming cycles (clip → re-rake → repeat), then a final hard clip with total restoration; (6) aggregates pseudo-rows to person weights; (7) emits feature values `1/weight` alongside weights.

Non-convergence raises `wf_error_convergence` carrying the group key, the worst dimension/category, and the last deviation — plus a pointer to the precheck finding that (almost always) predicted it.

---

## 8. Precheck: `wf_precheck()` (requirement 6)

Runs entirely before any iteration and returns a `wf_precheck` object whose core is a tidy issue table:

| column | content |
|---|---|
| `group` | group key ("*" for global issues) |
| `dim`, `category` | location of the issue (NA where not applicable) |
| `check` | machine name: `schema_missing_var`, `group_unmatched`, `cat_unknown_in_sample`, `cat_infeasible`, `support_thin`, `na_load`, `na_overload`, `feature_anomaly`, `dup_id`, `risk_extreme_ratio` |
| `severity` | `"error"` (blocks `wf_rake`), `"warning"`, `"note"` |
| `detail` | human-readable message with numbers |
| `data` | list-column of structured payload |

Two checks deserve emphasis because they encode hard-won lessons from real data. `cat_infeasible` fires when a target-positive category has zero (post-expansion) sample support — the exact Tibet failure mode — and is classified as an error because no amount of iteration can fix it. `risk_extreme_ratio` computes, per group and dimension, `target_share / sample_share` and flags ratios above a threshold (default 10) as warnings with the implied minimum weight inflation, together with a rough lower bound on the resulting design effect; this is what tells the analyst *before running anything* that education must be collapsed nationally, not patched province by province.

`wf_suggest_collapse(precheck, dims)` converts infeasible/thin findings into concrete `wf_collapse_plan` objects using the pre-registered ladders, which the user reviews and applies explicitly. The discipline loop is therefore: `precheck → (apply named remediations) → precheck again → rake → diagnose`, and every step leaves a provenance trace.

---

## 9. Diagnostics: `wf_diagnose()`

Per group: n (persons), n_effective (Kish ESS), design effect 1 + CV², mean/min/max weight, max/mean ratio, share of weights at trim bounds, residual margin error after trimming (max relative deviation per dimension), iterations, converged flag. Global summary: pooled ESS, worst groups, and a plain-language verdict line per group ("OK", "usable with caveats", "do not publish separately"). `print()` renders a compact table; `as.data.frame()` returns it raw for the user's reporting pipeline. A `plot()` method (histogram of weights per group, base graphics) is planned for 0.2.

Diagnostics never recompute weights; they read the `wf_weights` object plus, when residual-margin checks are requested, the original target — keeping execute and diagnose strictly separated.

---

## 10. Error and condition system (requirement 8)

All signals are classed conditions built by two internal helpers (`wf_abort()`, `wf_warn()`), each attaching a `data` payload:

| class | raised when |
|---|---|
| `wf_error_input` | malformed arguments, duplicate IDs, NA group keys, type problems |
| `wf_error_schema` | dimension/group variables missing; key maps referencing absent columns |
| `wf_error_feasibility` | infeasible categories; precheck errors blocking `wf_rake` |
| `wf_error_convergence` | IPF failed to converge within `max_iter` |
| `wf_error_internal` | invariant violations (a bug) — message asks the user to file an issue |
| `wf_warning_data` | dropped rows, feature anomalies handled by policy, thin support |
| `wf_warning_quality` | high design effect, trimming distorting margins beyond a threshold |

Rules: every message names the *location* (group/dim/category) and the *next action*; counts are always included ("7,874 of 117,788 reference rows (6.7%) have missing feature values"); errors are never raised from deep inside loops without context — the engine catches low-level failures and re-throws with group/dimension attached. `tryCatch(..., wf_error_feasibility = function(e) e$data$plan)` style programmatic handling is a documented, tested pattern.

---

## 11. Performance engineering (requirement 7)

Measured design targets: 32 groups × ~5k rows × 4 dimensions should complete in well under one second; 1M rows × 6 dimensions in a few seconds on a laptop.

The techniques, in order of importance: (1) **string work happens once** — all category matching is hoisted out of the iteration into integer index vectors; (2) **`rowsum()` for grouped sums** — C-level, no R-level per-category loops anywhere in the sweep; (3) **pre-split by group** — `split(seq_len(n), group_key)` once, then each group works on plain atomic vectors, never on data.frame subsets; (4) **no copies in the loop** — the weight vector is the only object mutated per sweep; (5) fractional expansion is built with `rep()`/index arithmetic, not `rbind()` in a loop.

Reserved acceleration paths (behind `Suggests:`, zero API change): a `data.table` fast path for target construction from very large population files (county-level joints with tens of millions of rows), and an optional Rcpp IPF kernel selected via `options(weightflow.engine = "cpp")` if profiling ever shows the R kernel to be the bottleneck (unlikely at national-survey scale). Groups are embarrassingly parallel; `wf_rake(..., parallel = TRUE)` via `parallel::mclapply` is planned for 0.2 with identical results guaranteed by per-group determinism.

---

## 12. Extensibility reserve (requirement 5)

The growth plan is organized around three stable seams:

**Seam 1 — target constructors.** New benchmark sources (census APIs, margins spreadsheets, pooled multi-year benchmarks) are new `wf_target_*()` functions producing the same canonical object. Nothing downstream changes.

**Seam 2 — method registry.** `wf_calibrate(sample, target, method = "raking", ...)` dispatches through an internal registry (`.wf_methods` environment) mapping method names to engine functions with a documented signature (`function(rows, target_group, control) -> list(w, log)`). `wf_rake()` is sugar for `method = "raking"`. Planned registrations: `"poststrat"` (full-joint cell weighting — the population data already supports it), `"linear"` and `"logit"` calibration (GREG-style, bounded weights by construction, reducing the need for trimming), `"propensity"` (online/offline propensity adjustment as a *first-stage* weight feeding raking as a second stage).

**Seam 3 — weight pipeline ledger.** `wf_weights` objects can be **chained**: `wf_compose(w_design, w_nonresponse, w_calib)` multiplies stages and concatenates provenance, so the package can grow into full production weighting (design weight → nonresponse adjustment → calibration → trimming → composite blending of online and offline via effective-sample-size λ, `wf_blend()`), with every stage inspectable. Replicate-weight variance estimation (`wf_replicates()`, jackknife/bootstrap) attaches at this seam too, since replicates are just the pipeline re-run on resampled data.

Namespace policy protecting the reserve: every exported symbol is prefixed `wf_`; S3 classes are frozen at 0.1 field names with additions allowed and removals forbidden until 1.0; the condition class taxonomy above is append-only.

---

## 13. Quality assurance

Testing (testthat): unit tests per constructor and per dirt case in the 4.1 table; property tests — margins match targets within tol, group totals preserved exactly, weight positivity, determinism across dimension orderings; an oracle test comparing against `survey::rake()` on shared inputs (skipped if survey absent); regression fixtures encoding the real pathological cases (a Tibet-like group: tiny n, dominant target category with near-zero support; a group with a fully-NA feature column; unmatched province keys). Continuous integration via GitHub Actions on release/oldrel/devel. `R CMD check --as-cran` clean is a merge requirement from day one, even while distribution is GitHub-only.

Documentation: roxygen2 for all exports; three vignettes — "The precheck→execute→diagnose workflow", "Bringing your own population data" (the key-map contract), and "Dirty data: NA, anomalies, and infeasibility" (built around the real failure modes).

Data policy: the package ships only a small **simulated** example dataset. Census-derived population tables are *not* redistributed (licensing is unclear for repackaged official statistics); instead the package documents the expected inputs and provides validators. This choice also keeps CRAN submission unproblematic.

Release plan: 0.1 GitHub-only (core: dims/targets/precheck/rake/diagnose/collapse), dogfooded on the current national survey; 0.2 adds composite weighting, post-stratification, parallel groups; CRAN submission considered once the API has survived two real production cycles unchanged.

---

## 14. Public API summary (0.1)

```
wf_dims()                 declare dimensions, levels, collapse ladders
wf_target_population()    canonical target from arbitrary population data (key-map contract)
wf_target_reference()     canonical target from a reference sample's feature values
wf_target_manual()        canonical target from a ready-made margins table
wf_target_shrink()        shrink a group target toward a national target
wf_precheck()             structured feasibility & dirt report (blocking vs advisory)
wf_suggest_collapse()     turn precheck findings into reviewable collapse plans
wf_apply_collapse()       apply a plan consistently to sample + target (provenance-logged)
wf_rake()                 execute (fractional NA handling, trimming, per-group IPF)
wf_diagnose()             per-group quality table + verdicts
wf_compose(), wf_blend()  reserved seams (0.2): weight chaining, online/offline blending
```

Everything below this line in the repository is `R/core.R` — the reference implementation of the 0.1 core.
