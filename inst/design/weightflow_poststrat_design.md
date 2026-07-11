# weightflow — Design Document, Extension 1

**Cell-level post-stratification with adaptive nested collapsing**

Companion to `weightflow_design.md`. Target version: 0.2.0. This extension adds a second calibration method (`method = "poststrat"`) on the reserved Seam 2, plus its precheck-side collapse planner. It introduces no breaking change: every 0.1 class, constructor, and condition is reused unchanged; the only additive change to an existing class is one optional field on `wf_target` (`joint`), described in §3.

The scope here is deliberately narrow — **single-source** post-stratification only. Fusing an online (raked) source with an offline (post-stratified) source is a separate Seam 3 concern (`wf_blend()`) and is explicitly out of scope for this document, per the requirement that `wf_poststrat()` remain single-purpose and independently testable.

---

## 1. Why post-stratification, and how it differs from raking

Raking (0.1) aligns **marginal** totals: for the current project, 2 + 2 + 5 + 5 = 14 numbers per province. It never promises that the 2×2×5×5 = 100 **joint cells** match the population, and in practice they do not — which is exactly the gap the user observed after raking (a cell's weighted total ≠ that cell's population head count).

Post-stratification aligns the **joint cells** directly: each cell's weighted total is forced to equal the population count for that cell. This is strictly stronger than raking — if every cell matches, every margin matches automatically, and the province total is preserved. It is also simpler (one closed-form scaling per cell, no iteration).

Post-stratification has exactly two failure modes, and everything in this extension exists to manage them:

1. **Empty cells** (zero sample support): a population-positive cell with no respondents. Pure post-stratification would assign weight 0 to a cell that should represent real people. Unsolvable by scaling; must be handled structurally (§7).
2. **Sparse cells** (few respondents): a cell supported by 1–4 respondents gets an enormous, unstable weight, inflating the design effect. Managed by collapsing (§5).

The method therefore is not "post-stratify the 100 cells" but "post-stratify the *finest partition each cell can support*, falling back through a declared ladder where support is thin, and redistributing where support is absent."

---

## 2. Requirements captured (from user decisions)

| # | Decision | Consequence in this design |
|---|---|---|
| 1 | Sparsity threshold = **user-supplied minimum cell sample count**; fallback ladder is **pre-declared** (never auto-invented) | `min_cell` is a required numeric; collapsing consumes a declared `wf_collapse_ladder` (§4). No implicit merging. |
| 2 | Collapsing is **adaptive first** (per-cell nesting), **falls back to province-uniform** partition if adaptive still leaves problems | `granularity = "adaptive"` default, with automatic degradation to `"province"` when adaptive cannot resolve all cells (§6). |
| 3 | Output must include an **audit/report-friendly mapping table** | `wf_poststrat` returns `cell_report` + `collapse_map` (§8). |
| 4 | **Calibration-style** weighting (respect initial weights; post-strat multiplies a calibration factor) | `mode = "calibration"` is the only supported mode here; initial weights are the base, not overwritten (§7). |
| 5 | Empty cells → **redistribute** their population to other cells | `empty_cell = "redistribute"` default (§7.3). |
| 6 | **Single-source only**; no fusion inside this function | No `w_online`/`w_offline` arguments; fusion deferred to `wf_blend()`. |
| 7 | The function **outputs and enforces a province-total constraint** | Province (group) totals are a hard post-condition, asserted and reported (§7.4). |

---

## 3. Data model additions

### 3.1 One optional field on `wf_target`: `joint`

The 0.1 `wf_target` stores only per-group **margins**. Post-stratification needs the full **joint** cell table. Rather than a new class, we add one optional element:

```r
tgt$joint  # named list, one element per group; each is a data.frame:
           #   columns = the dimension variables (character keys) + `pop`
           #   one row per non-empty population cell
```

`joint` is populated by `wf_target_population(..., keep_joint = TRUE)`. When absent (0.1 behavior, `keep_joint = FALSE` default), raking still works and `wf_poststrat()` raises `wf_error_schema` instructing the user to rebuild the target with `keep_joint = TRUE`. Margins remain present and are used for the province-total constraint and for validation, so no downstream 0.1 code path changes.

Rationale for a joint **data.frame** (not a 4-D array): the classification is schema-agnostic (any number of dimensions, any level counts), arrays would require dynamic `dim`/`aperm` gymnastics and blow up memory for high-dimensional cross-classifications, whereas a long data.frame of only non-empty cells is compact (structural-zero cells never appear) and matches the sample side, which is also long. Cell identity everywhere is the ordered tuple of character keys, hashed to a single string key (`.wf_cell_key()`).

### 3.2 New classes

| Class | Constructor | Role |
|---|---|---|
| `wf_collapse_ladder` | `wf_collapse_ladder()` | An **ordered, pre-declared** sequence of collapse steps (each step a per-dimension category map). Defines the *only* merges the planner is permitted to apply. |
| `wf_poststrat_plan` | `wf_plan_poststrat()` | Per-group, per-cell resolution: which ladder level each original cell is evaluated at, and the resulting partition. Reviewable before execution. |

`wf_weights` (returned by `wf_poststrat`) is the **same class** as raking returns, so `wf_diagnose()` and any pipeline code consume it identically. Two named fields are added to its list (`cell_report`, `collapse_map`); the print method gains a one-line post-strat summary via method dispatch on `provenance$method`.

---

## 4. Pre-declared collapse ladders (`wf_collapse_ladder`)

The ladder is the user's explicit contract for *how* cells may be coarsened. It is an ordered list of levels 0..L, where level 0 is the finest (the raw cells) and each subsequent level applies one additional declared merge:

```r
ladder <- wf_collapse_ladder(
  dims,                                  # the wf_dims object (for validation)
  level1 = list(edu5 = c(`1`="12", `2`="12", `3`="3", `4`="45", `5`="45")),
  level2 = list(age5 = c(`1`="1", `2`="2", `3`="3", `4`="45", `5`="45")),
  level3 = list(edu5 = c(`12`="LM", `3`="LM", `45`="H"))   # merges are cumulative
)
```

Semantics and guarantees:

- **Ordered and cumulative.** Level *k* is level *k−1* with its additional maps applied. `wf_plan_poststrat()` walks *up* the ladder cell by cell until support is met.
- **Validated at construction.** Every map key must be a declared level of its dimension (or a category produced by an earlier ladder level, enabling multi-step merges as in `level3`). Unknown categories → `wf_error_input`. This prevents silent typos from becoming silent merges.
- **Declared, never inferred.** There is no `"auto"` ladder. If the ladder is exhausted and a cell is still short, the engine does not invent a coarser partition; it degrades to province-uniform (§6) and, failing that, treats the residual as empty (§7.3).
- **Reusable object.** A ladder validated once can be reused across surveys sharing the same schema, and is serialized into provenance.

---

## 5. Sparsity resolution algorithm

For one group, with user threshold `min_cell` (minimum respondent count per resolved cell):

1. Compute raw cell counts at ladder level 0 (finest) from the sample.
2. **Adaptive pass** (`granularity = "adaptive"`): each original cell is assigned the *lowest ladder level at which the coarsened cell it belongs to meets `min_cell`*. Cells with ample support stay at level 0 (full 100-cell resolution); only thin cells climb. Because merges are cumulative and monotone (coarser cells have ≥ the support of any finer cell within them), a cell's minimal satisfying level is well-defined; if no ladder level satisfies it, the cell is flagged `unresolved`.
3. If any cell is `unresolved`, degrade this group to the **province-uniform pass** (§6).
4. Cells still unresolved after province-uniform (i.e. even the coarsest ladder level has < `min_cell`, or the coarsened cell has zero support) are handed to empty-cell handling (§7.3).

The threshold is on **sample count**, exactly as specified (requirement 1) — not on effective sample size — keeping the rule transparent and independent of the weighting result. (An `neff`-based option is noted as a future switch in §11 but is not implemented in 0.2.)

---

## 6. Granularity: adaptive with province-uniform fallback (requirement 2)

`granularity = "adaptive"` (default) implements §5 step 2: a *mixed-resolution* partition where different cells within the same province sit at different ladder levels. This maximizes retained detail — well-supported cells keep full joint calibration; only thin regions are coarsened. The cost is a more complex partition to report, which is exactly why `cell_report` (§8) exists.

When the adaptive pass leaves any cell unresolved (§5 step 3), the group **degrades to `granularity = "province"`**: a single ladder level is chosen for the *entire* province — the lowest level at which **all** cells meet `min_cell`. This trades detail for guaranteed uniform feasibility and a simpler partition. The degradation is automatic, recorded in provenance (`granularity_used` per group may differ from the requested value), and surfaced as a `wf_warning_quality`. A user may also request `granularity = "province"` directly to skip the adaptive attempt.

This ordering — try adaptive, fall back to uniform — is the literal encoding of the user's decision 2.

---

## 7. Execution: `wf_poststrat()`

### 7.1 Signature

```r
wf_poststrat(
  sample, target,
  init_weight = NULL,                 # column name; NULL => all 1 (req. 4 base)
  min_cell,                           # REQUIRED integer >= 1 (req. 1)
  ladder,                             # wf_collapse_ladder (req. 1)
  granularity = c("adaptive","province"),   # (req. 2)
  empty_cell = c("redistribute","flag","error"),  # default redistribute (req. 5)
  id = NULL,
  precheck = TRUE,
  tol = 1e-8                          # province-total assertion tolerance (req. 7)
)
```

### 7.2 Calibration-style weighting (requirement 4)

Weighting is calibration, not replacement. For each resolved cell *c* in group *g*:

```
factor_c = pop_c / sum(init_weight over respondents in c)
final_weight_i = init_weight_i * factor_c        for i in cell c
```

The initial weight is honored as the base; post-stratification applies a single multiplicative calibration factor per resolved cell. With `init_weight = NULL` (all 1s) this reduces to classic post-stratification (weight = pop_c / n_c), so the classic case is a special case of the calibration formula rather than a separate code path. Within a coarsened (resolved) cell, the ratio of two respondents' final weights equals the ratio of their initial weights — i.e. the design information carried by `init_weight` is preserved through the merge, which is the whole point of doing this calibration-style for an offline design sample.

### 7.3 Empty-cell redistribution (requirement 5, option b)

A resolved cell with population > 0 but **zero** sample support (even at the coarsest ladder level) cannot receive weight. Its population is **redistributed** to the cells that *do* have support, proportionally to those cells' population, **within the smallest enclosing coarser cell that has support** — not globally across the province, which would distort unrelated regions. Concretely: climb one more ladder level to find the nearest supported ancestor cell, and fold the orphan population into that ancestor's target before computing factors. If even the whole province has no support anywhere (degenerate), raise `wf_error_feasibility`.

Every redistribution is logged in `cell_report` (orphan cell, receiving cell, population moved), so the analyst can see exactly which population was reallocated and audit whether the exchangeability assumption implied by the redistribution is acceptable. `empty_cell = "flag"` instead marks orphan cells and leaves their population unassigned (province total will then be short by the orphan population — reported, not silently absorbed); `"error"` refuses.

### 7.4 Province-total constraint (requirement 7)

After weighting, for every group the sum of final weights must equal the group's population total (the sum over its joint cells, which by §3 equals the sum of its margins). This is asserted to within `tol`; violation raises `wf_error_internal` (it would indicate a redistribution or factor bug). Under `empty_cell = "flag"`, the constraint target is reduced by the flagged orphan population and the shortfall is reported explicitly. The realized per-group total and its deviation from the population total are returned in the group log, so the constraint is both **enforced and reported**, as required.

### 7.5 Algorithm summary (per group)

resolve levels (§5/§6) → build resolved-cell key for every respondent → redistribute orphan population into supported ancestors (§7.3) → compute per-cell calibration factors on `init_weight` (§7.2) → assert province total (§7.4) → assemble `cell_report`. All grouped sums use `rowsum()` on integer cell indices; no iteration is needed (post-strat is closed-form), so this is markedly faster than raking.

---

## 8. Outputs: audit and reporting (requirement 3)

`wf_poststrat()` returns a `wf_weights` object with:

- `data`: `id`, `group`, resolved-cell key, `weight`, `feature = 1/weight`.
- `cell_report` (**the audit table**): one row per *original* (level-0) population cell, with columns `group`, the dimension keys, `pop`, `n_sample`, `ladder_level_used`, `resolved_cell` (the key of the coarsened cell it was calibrated within), `granularity_used`, `orphan` (logical), `redistributed_to`, `pop_moved`, `final_cell_weight_mean`. This answers "which original cells were merged into what, why (support), and with what population movement" at a glance.
- `collapse_map`: a compact `wf_poststrat_plan` mapping (group × original-cell → resolved-cell + level), reusable and serializable.
- `log`: per group — `n`, `n_cells_raw`, `n_cells_resolved`, `granularity_used`, `n_orphan_cells`, `pop_redistributed`, `total_target`, `total_realized`, `total_dev`, `deff`.
- `provenance`: as in 0.1, plus `method = "poststrat"`, `min_cell`, ladder hash, per-group `granularity_used`.

`wf_diagnose()` consumes this unchanged (design effect, ESS, verdicts per group). A `summary()` method on `cell_report` prints the merge/redistribution summary for a methods appendix.

---

## 9. Precheck integration (`wf_plan_poststrat()`, discipline preserved)

Mirroring 0.1's precheck→execute discipline, `wf_plan_poststrat()` runs the resolution logic **without weighting** and returns the `wf_poststrat_plan` plus a diagnostic table (per group: cells needing collapse, cells reaching each ladder level, orphan cells, whether adaptive suffices or province degradation is forced). The user reviews the plan, and may pass it directly to `wf_poststrat(plan = ...)` to skip re-resolution. `wf_poststrat(precheck = TRUE)` runs it internally and aborts on structural infeasibility (e.g. empty ladder against present sparsity with `empty_cell = "error"`). The loop is therefore: `wf_plan_poststrat → (review) → wf_poststrat → wf_diagnose`.

---

## 10. Error and condition system (reused, extended)

No new condition classes — the 0.1 taxonomy suffices. New situations map onto existing classes:

| Situation | Class | Severity |
|---|---|---|
| Target built without `keep_joint` | `wf_error_schema` | error |
| `min_cell` missing / < 1 / non-integer | `wf_error_input` | error |
| Ladder map references unknown category | `wf_error_input` | error |
| Cell unresolved and `empty_cell = "error"` | `wf_error_feasibility` | error |
| Whole group has no support anywhere | `wf_error_feasibility` | error |
| Province total assertion fails | `wf_error_internal` | error (bug) |
| Adaptive degraded to province-uniform | `wf_warning_quality` | warning |
| Orphan population redistributed | `wf_warning_data` | warning |
| Resolved cell still thin after coarsening | `wf_warning_quality` | warning |

All carry structured `data` payloads (group, cell key, level, populations) for programmatic handling, consistent with P5.

---

## 11. Performance and extensibility reserve

Post-stratification is closed-form: one `rowsum()` per group for cell counts, one for initial-weight sums, vector arithmetic for factors — O(n) per group, no iteration, faster than raking. Resolution is precomputed once as integer level assignments. Cell keys are built once via a single `paste()` on character columns, then `match()`ed to integer indices; the hot path touches no strings. Groups remain embarrassingly parallel (reserved `parallel = TRUE`, 0.2+).

Reserved switches, none altering the 0.2 API: `min_cell_by = "neff"` (threshold on effective sample size rather than raw count); `redistribute = "model"` (hand orphan cells to an MRP-style predictor instead of proportional reallocation — the natural bridge to a future `method = "mrp"` on Seam 2); and registration of `"poststrat"` in the `.wf_methods` registry so `wf_calibrate(method = "poststrat")` dispatches to it, unifying the method interface with raking.

---

## 12. Public API additions (0.2)

```
wf_collapse_ladder()   declare the ordered, cumulative, validated merge ladder
wf_plan_poststrat()    resolve cells to ladder levels WITHOUT weighting (precheck)
wf_poststrat()         calibration-style cell post-stratification; province-total enforced
                       + adaptive→province-uniform granularity
                       + empty-cell redistribution into nearest supported ancestor
                       + cell_report / collapse_map audit outputs
summary.wf_poststrat_plan(), summary(cell_report)   reporting helpers
```

`wf_target_population()` gains one argument: `keep_joint = FALSE`. Everything else in 0.1 is untouched.

---

The reference implementation of the above is `weightflow_poststrat.R`, sourced after `weightflow_core.R`.
