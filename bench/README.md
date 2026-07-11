# WFC performance baseline

The 0.9.1 benchmark exercises the two workloads committed in the core design:
32 groups with 5,000 rows and four calibration dimensions, plus an optional
one-million-row case with six dimensions.

Install the current package, then run:

```sh
Rscript bench/benchmark-0.9.1.R
Rscript bench/benchmark-0.9.1.R --full
```

The script uses fixed seeds, base R, no trimming, and the normal precheck. It
reports elapsed time together with margin and group-total errors so a faster run
cannot hide a correctness regression. Timing is an observed baseline rather
than a CRAN test: shared CI runners are too variable for a hard wall-clock gate.

Committed measurements belong in `results-0.9.1.md` with the exact R version,
platform, processor architecture, and command used.
