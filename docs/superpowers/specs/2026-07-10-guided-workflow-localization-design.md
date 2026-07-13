# WFC Guided Workflow and Localization 0.11.0 Design

## Goal

Ship the first non-specialist path over the existing WFC engine. Version 0.11
adds `wf_autoweigh()` and bilingual human-facing output while preserving the
same constructors, prechecks, calibration engines, diagnostics, conditions,
and audit artifacts used by the expert path.

The release implements P7-P9 from `inst/design/wfc_future_design.md`:

- explain what happened, why, and what to do next;
- one engine with an expert path and a guided orchestration path;
- English internals with localizable rendering only.

All project copyright remains with WEIAN DATA TECH (Beijing) Co., Ltd. Every
commit is authored and committed as `Kunxiang Ma <makunxiang@weiandata.com>`.

## Scope

### Included

1. English and Simplified Chinese catalogs under `inst/i18n/`.
2. Internal language resolution and translation helpers.
3. Localized reports, manager verdict labels, plot labels, and guided-workflow
   narration.
4. `wf_autoweigh()` with target construction, precheck/remediation loop,
   method selection, optional trim recommendation/application, calibration,
   diagnostics, report, and decision ledger.
5. `wf_autoweigh_result` print support and complete release documentation.

### Excluded

- Localization of error/warning condition messages, R documentation, code, or
  stable object/column names.
- survey/srvyr/broom bridges and WFCstudio (0.12).
- serialized pipelines, drift validation, and audit JSON (0.13).
- new statistical estimators or changes to numerical engine semantics.

## Localization Architecture

Catalogs are single-record DCF files:

- `inst/i18n/en.dcf`
- `inst/i18n/zh_CN.dcf`

They must contain identical keys. Production code loads them lazily through an
internal cache and reads them with base R `read.dcf()`; no dependency is added.

Language resolution order:

1. explicit `lang` argument;
2. `options(wfc.lang = ...)`;
3. `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG`, and `LC_CTYPE`;
4. English fallback.

Accepted explicit aliases normalize to `en` or `zh_CN` (`en`, `en_US`,
`en-GB`, `zh`, `zh_CN`, `zh-CN`). An unsupported explicit argument or option
raises `wf_error_input`; an unrecognized session locale falls back to English.

`.wf_tr(key, ..., lang)` interpolates catalog strings with `sprintf()`. Missing
keys in the selected catalog fall back to English; a key missing from English
raises `wf_error_internal`. Translation affects rendering only. Stable actions,
condition classes, data-frame column names, and ledger `detail_key` values stay
English and machine-readable.

## Existing Output Changes

### `wf_report()`

The existing `lang` argument becomes active. Structured tables keep English
column names and stable fields. Manager reports gain localized
`verdict_label`/`action` text while retaining `verdict` and `light`. Markdown
and HTML translate the title, audience label, section headings, and known
column labels. `report$language` stores the normalized language.

### Plot methods

Every 0.10 plot method gains `lang = NULL` as an explicit formal argument:

- `plot.wf_weights()`
- `plot.wf_diagnostics()`
- `plot.wf_auto_trim()`
- `plot.wf_blend_result()`
- `plot.wf_propensity_weights()`

Titles, axes, and legends are translated; group/category values remain user
data and are not translated.

## Guided Workflow API

```r
wf_autoweigh(
  sample, population, dims,
  key_map = NULL, count = NULL,
  by = NULL, id = NULL,
  method = c("auto", "raking", "poststrat", "logit"),
  ladder = NULL, min_cell = NULL,
  bounds = c(0.3, 3),
  trim = "auto",
  max_deff = 6, max_residual = 0.02,
  interactive = base::interactive(),
  lang = NULL,
  ...
)
```

`population` may be a ready `wf_target` or a raw data frame. Raw data requires
`key_map` and `count`; target construction retains joint cells when
post-stratification is selected.

### Method selection

- Explicit methods are honored.
- `method = "auto"` selects post-stratification only when both a ladder and
  `min_cell` are supplied; otherwise it selects raking.
- Auto mode never selects bounded logit calibration because choosing bounds is
  an analyst judgment.

### Discipline loop

1. Build or validate target.
2. Run `wf_precheck()`.
3. If blocked, call `wf_suggest_collapse()` using only maps declared in
   `dims`.
4. If no declared remediation exists, raise `wf_error_feasibility`; never
   bypass the precheck.
5. In interactive mode ask before applying a collapse or finite trim. In
   non-interactive mode apply only declared/reproducible recommendations and log
   them.
6. Re-run precheck after each collapse until clean or no progress is possible.
7. For raking with `trim = "auto"`, call `wf_auto_trim()`. Apply a finite
   recommendation, skip when `Inf`, and continue untrimmed when `NA` while
   recording the outcome.
8. Execute the selected existing engine, diagnose, and build the manager report.

`trim` accepts `"auto"`, `NULL`, or a numeric two-element bound. Automatic
trimming applies only to raking. Post-stratification requires a reviewed
`wf_collapse_ladder` (or `$ladder` from `wf_ladder_draft`) and positive
`min_cell`. Logit requires valid `bounds` and ignores trim automation.

## Decision Ledger

The returned `wf_autoweigh_result` contains:

- `$weights`, `$diagnostics`, `$report`;
- `$ledger`: ordered data frame with `step`, stable `action`, stable
  `detail_key`, localized `detail`, `artifact_class`, and `time`;
- `$artifacts`: corresponding structured objects (`wf_precheck`,
  `wf_collapse_plan`, `wf_auto_trim`, etc.);
- final `$sample`, `$target`, normalized `$language`, and `$method`.

Actions include `start`, `target`, `precheck`, `collapse`, `trim`, `calibrate`,
and `done`. The localized text is for humans; `action` and `detail_key` are the
stable programmatic interface.

## Conditions and Interactivity

Errors remain English and classed. Validation uses existing classes:

- malformed arguments/language/method controls: `wf_error_input`;
- missing raw target mapping or sample columns: `wf_error_schema`;
- unresolved precheck, declined required remediation, or impossible method
  setup: `wf_error_feasibility`.

Interactive confirmation is isolated in an internal helper so it can be tested
without changing the public API. Declining a proposal stops before weights are
produced.

## Testing Strategy

- Catalog parity, alias normalization, explicit/option/locale precedence,
  fallback, interpolation, and unknown-key behavior.
- English and Chinese manager reports, Markdown/HTML headings and column labels,
  while stable table names remain English.
- Every plot method accepts English/Chinese language selection on a PDF device.
- Clean raw-population and ready-target guided runs.
- Auto raking, explicit logit, and auto post-stratification routing.
- Declared collapse remediation, unresolved failures, and no input mutation.
- Automatic trim application/no-op/no-solution ledger paths.
- Localized narration and stable decision-ledger keys.
- Existing 0.10 APIs remain green; coverage >= 80%; all vignettes build;
  `R CMD check --as-cran --no-manual` has no error or warning.

## Release Tasks

- Add catalogs, i18n helpers, guided orchestration, tests, and S3 methods.
- Localize report and plot rendering without changing stable schemas.
- Add bilingual README guidance and a guided-workflow vignette.
- Bump to 0.11.0, regenerate documentation, and update CRAN notes.
- Run full release gates and build `WFC_0.11.0.tar.gz`.
