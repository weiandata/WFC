# Examples

Use this directory for small, safe, reproducible examples that help a reader
understand or verify the project. Examples must not contain business logic,
secrets, personal information, restricted client information, or unapproved
data.

A generated repository may add:

- **Example code** showing the smallest supported usage path.
- **Example dataset** using synthetic, public, or explicitly authorized data
  with provenance and schema notes.
- **Example notebook** with deterministic inputs, recorded environment
  requirements, and reproducible outputs.
- **Example workflow** showing an end-to-end process and its validation steps.

## Bundled verified-target import examples

The package installs two synthetic tables under `inst/extdata/`:

- `safe-target-example.csv`
- `safe-target-example.xlsx`

Each has a separate companion file named by appending `.source.dcf` to the full
data filename. This is intentional: CSV and Excel bytes have different SHA-256
checksums even when their visible tables are identical.

```r
library(WFC)

dims <- wf_dims(sex = c("F", "M"), age = c("18-34", "35+"))
csv <- system.file("extdata", "safe-target-example.csv", package = "WFC")
target <- wf_import_target(
  csv,
  paste0(csv, ".source.dcf"),
  dims,
  key_map = c(sex = "sex", age = "age"),
  count = "count",
  production = FALSE
)
```

The bundled records say `demo_only: true`; they demonstrate file layout and
must not be used as real population authority. For a new source, call
`wf_target_template()` with a new `.csv` or `.xlsx` path, fill the target data,
complete every source field before looking at study outcomes, and update the
recorded checksum. A blank source record is expected to block until completed.

The complete prepare/import/plan/approve/execute/attach/report workflow and AI
Agent refusal contract are in `vignette("safe-weighting-workflow")`.
