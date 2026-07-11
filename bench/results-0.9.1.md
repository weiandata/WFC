# WFC 0.9.1 benchmark results

Run on 2026-07-10 with:

```sh
R_LIBS=/private/tmp/wfc-lib Rscript bench/benchmark-0.9.1.R --full
```

Environment: WFC 0.9.1; R 4.6.0; `aarch64-apple-darwin23`; macOS Tahoe
26.5.1; base R BLAS/LAPACK.

| Case | Rows | Groups | Dimensions | Repetitions | Median seconds | Max seconds | Max relative margin error | Max absolute group-total error |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 32 groups x 5,000 rows | 160,000 | 32 | 4 | 3 | 0.295 | 0.296 | 3.71e-11 | 1.00e-10 |
| One million rows | 1,000,000 | 32 | 6 | 1 | 2.622 | 2.622 | 8.78e-11 | 1.54e-09 |

Both cases meet the core design targets on this machine: the national-survey
case completes well under one second and the one-million-row case completes in
a few seconds. These measurements are a regression baseline, not a portable
wall-clock guarantee.
