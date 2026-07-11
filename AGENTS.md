# AGENTS.md

## Ownership Policy (Highest Priority)

All copyright in this project belongs 100% to WEIAN DATA TECH (Beijing) Co.,
Ltd. (惟安数据科技（北京）有限公司). All git commits must be authored and
committed as `WEIAN DATA <contact@weiandata.com>` (enforced via local git
config; never commit under a personal identity). Any new file, document, or
release that carries an attribution or copyright notice must name WEIAN DATA
TECH as the copyright holder. For CRAN compliance, `DESCRIPTION` keeps
Kunxiang Ma as maintainer (`cre`) while the company holds `cph` and `fnd`
roles. This policy overrides all other conventions in this repository.

## Project Authority

Follow the design documents under `inst/design/` as the design authority:
`weightflow_design.md` (core), `weightflow_poststrat_design.md` (Extension 1),
`weightflow_roadmap_design.md` (Extension 2), and `wfc_future_design.md`
(Extension 3, the 0.10 -> 1.0 roadmap). Reference prototypes live under
`inst/reference/`: `weightflow_core.R` / `weightflow_poststrat.R` for the
shipped engines and the `wfc_future_*.R` files for roadmap features. The
package was renamed from `weightflow` to `WFC` at 0.9.0; historical file names
keep the old name on purpose.

## Language Policy

Use English for package code, tests, documentation, configuration, and commit
messages. The only Chinese-language repository file is `README.zh-CN.md`.
Working documents in Chinese live in the local `ZH/` folder, which is
git-ignored and build-ignored; do not commit its contents.

## Data Policy

Files under `private-data/` are local private source data. Do not commit them,
read them into examples, or include them in package builds. Package examples use
only simulated data generated from `data-raw/make-wfc-example.R`.

## Development Policy

Use test-driven development for behavior changes. Run focused tests after each
change, then run the full package verification before claiming completion.

## Git Policy

Stage files intentionally. Do not add private source data, local build outputs,
`.codegraph/`, `.DS_Store`, or generated check directories.
