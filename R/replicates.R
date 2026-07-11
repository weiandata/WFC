#' Return the loaded package version for provenance.
#'
#' @keywords internal
#' @noRd
.wf_replicates_package_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("WFC")),
    error = function(e) "0.7.0"
  )
}

#' Resolve the sampling design (strata and PSUs) from data columns.
#'
#' @param data Input data frame.
#' @param strata Stratum column name or `NULL` (single stratum).
#' @param clusters PSU column name or `NULL` (each row is its own PSU).
#' @keywords internal
#' @noRd
.wf_design <- function(data, strata, clusters) {
  n <- nrow(data)
  if (!is.null(strata)) {
    if (length(strata) != 1 || !is.character(strata) ||
        !strata %in% names(data)) {
      wf_abort("`strata` must name a column in `data`.",
               "wf_error_input", list(strata = strata))
    }
    stratum <- .chr(data[[strata]])
  } else {
    stratum <- rep("1", n)
  }
  if (!is.null(clusters)) {
    if (length(clusters) != 1 || !is.character(clusters) ||
        !clusters %in% names(data)) {
      wf_abort("`clusters` must name a column in `data`.",
               "wf_error_input", list(clusters = clusters))
    }
    cluster <- .chr(data[[clusters]])
  } else {
    cluster <- as.character(seq_len(n))
  }

  pairs <- unique(data.frame(stratum = stratum, cluster = cluster,
                             stringsAsFactors = FALSE))
  dup <- pairs$cluster[duplicated(pairs$cluster)]
  if (length(dup) > 0) {
    wf_abort(
      sprintf("Clusters are not nested within strata: %s appear in >1 stratum.",
              paste(unique(dup), collapse = ", ")),
      "wf_error_design", list(clusters = unique(dup))
    )
  }

  strata_levels <- unique(stratum)
  psu <- lapply(strata_levels, function(h) unique(cluster[stratum == h]))
  names(psu) <- strata_levels
  list(n = n, stratum = stratum, cluster = cluster,
       strata = strata_levels, psu = psu)
}

#' Rao-Wu rescaled bootstrap multipliers.
#'
#' @param design A `.wf_design()` result.
#' @param R Number of replicates.
#' @param seed Optional integer seed.
#' @keywords internal
#' @noRd
.wf_boot_mult <- function(design, R, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  n <- design$n
  mult <- matrix(1, n, R)
  for (h in design$strata) {
    psus <- design$psu[[h]]
    nh <- length(psus)
    if (nh < 2) next
    units_by_psu <- lapply(psus, function(p) {
      which(design$stratum == h & design$cluster == p)
    })
    for (r in seq_len(R)) {
      draw <- sample.int(nh, nh - 1, replace = TRUE)
      counts <- tabulate(draw, nbins = nh)
      a <- (nh / (nh - 1)) * counts
      for (i in seq_len(nh)) {
        mult[units_by_psu[[i]], r] <- a[i]
      }
    }
  }
  list(mult = mult, scale = 1 / R, rscales = rep(1, R))
}

#' Stratified delete-one-PSU jackknife multipliers.
#'
#' @param design A `.wf_design()` result.
#' @keywords internal
#' @noRd
.wf_jack_mult <- function(design) {
  n <- design$n
  cols <- list()
  rscales <- numeric(0)
  for (h in design$strata) {
    psus <- design$psu[[h]]
    nh <- length(psus)
    in_h <- design$stratum == h
    if (nh < 2) {
      wf_warn(
        sprintf("Stratum '%s' has a single PSU; it cannot be jackknifed and contributes no replicate.", h),
        "wf_warning_quality", list(stratum = h)
      )
      next
    }
    for (p in psus) {
      m <- rep(1, n)
      m[in_h] <- nh / (nh - 1)
      m[in_h & design$cluster == p] <- 0
      cols[[length(cols) + 1]] <- m
      rscales <- c(rscales, (nh - 1) / nh)
    }
  }
  if (length(cols) == 0) {
    wf_abort("No stratum has >= 2 PSUs; jackknife has no replicates.",
             "wf_error_design")
  }
  list(mult = do.call(cbind, cols), scale = 1, rscales = rscales)
}

#' Sylvester-construction Hadamard matrix of order >= `n` (a power of two).
#'
#' @param n Minimum order.
#' @keywords internal
#' @noRd
.wf_hadamard <- function(n) {
  k <- 1
  while (k < n) k <- k * 2
  H <- matrix(1, 1, 1)
  while (nrow(H) < k) {
    H <- rbind(cbind(H, H), cbind(H, -H))
  }
  H
}

#' Balanced Repeated Replication multipliers (standard or Fay half-sampling).
#'
#' @param design A `.wf_design()` result; every stratum must have 2 PSUs.
#' @param rho Fay's BRR shrinkage parameter in `[0, 1)`.
#' @keywords internal
#' @noRd
.wf_brr_mult <- function(design, rho = 0) {
  sizes <- vapply(design$psu, length, integer(1))
  bad <- design$strata[sizes != 2]
  if (length(bad) > 0) {
    wf_abort(
      sprintf("BRR requires exactly 2 PSUs per stratum; not met by: %s.",
              paste(bad, collapse = ", ")),
      "wf_error_design", list(strata = bad)
    )
  }
  H <- length(design$strata)
  hmat <- .wf_hadamard(H + 1)
  R <- nrow(hmat)
  n <- design$n
  mult <- matrix(1, n, R)
  high <- 2 - rho
  low <- rho
  for (hi in seq_along(design$strata)) {
    h <- design$strata[hi]
    psus <- design$psu[[h]]
    in_h <- design$stratum == h
    u1 <- in_h & design$cluster == psus[1]
    u2 <- in_h & design$cluster == psus[2]
    for (r in seq_len(R)) {
      if (hmat[r, hi + 1] > 0) {
        mult[u1, r] <- high
        mult[u2, r] <- low
      } else {
        mult[u1, r] <- low
        mult[u2, r] <- high
      }
    }
  }
  list(
    mult = mult,
    scale = 1 / (R * (1 - rho)^2),
    rscales = rep(1, R)
  )
}

#' Generate re-calibrated replicate weights for variance estimation.
#'
#' Perturbs base weights by bootstrap, jackknife, or BRR multipliers and
#' re-runs a calibration pipeline (`refit`) on each replicate, so the resulting
#' variance captures calibration uncertainty. Pair with [wf_variance()].
#'
#' @param data Input data frame (one row per unit).
#' @param refit A closure `function(data, weights) -> wf_weights` that re-runs
#'   the calibration pipeline using `weights` as the base/initial weights.
#' @param method Replication method.
#' @param R Number of bootstrap replicates (ignored for jackknife / BRR).
#' @param strata Optional stratum column name (single stratum if `NULL`).
#' @param clusters Optional PSU column name (each row is its own PSU if `NULL`).
#' @param id Optional id column aligning replicate weights (row order if `NULL`).
#' @param base_weight Optional starting base-weight column (all `1` if `NULL`).
#' @param seed Optional integer seed for the bootstrap draws.
#' @param rho Fay's BRR shrinkage parameter in `[0, 1)`. Used only when
#'   `method = "brr"`; `rho = 0` gives standard BRR.
#' @param parallel Whether to re-run replicate refits with forked parallelism
#'   where available. Windows falls back to serial execution.
#' @param progress Whether to show a `cli` progress bar when `cli` is installed.
#' @return A `wf_replicate_weights` object.
#' @export
wf_replicates <- function(data, refit,
                          method = c("bootstrap", "jackknife", "brr"),
                          R = 500, strata = NULL, clusters = NULL,
                          id = NULL, base_weight = NULL, seed = NULL,
                          rho = 0, parallel = FALSE, progress = FALSE) {
  if (!is.data.frame(data) || nrow(data) == 0) {
    wf_abort("`data` must be a non-empty data frame.", "wf_error_input")
  }
  if (!is.function(refit)) {
    wf_abort("`refit` must be a function(data, weights) returning a wf_weights.",
             "wf_error_input")
  }
  method <- match.arg(method)
  if (method == "bootstrap" &&
      (length(R) != 1 || !is.finite(R) || R < 1 || R != as.integer(R))) {
    wf_abort("`R` must be a positive integer.", "wf_error_input", list(R = R))
  }
  if (length(rho) != 1 || !is.numeric(rho) || !is.finite(rho) ||
      rho < 0 || rho >= 1) {
    wf_abort("`rho` must be one finite number in [0, 1).", "wf_error_input")
  }
  if (method != "brr" && rho != 0) {
    wf_abort("`rho` is only used when method = 'brr'.", "wf_error_input")
  }
  n <- nrow(data)
  if (!is.null(id)) {
    if (length(id) != 1 || !is.character(id) || !id %in% names(data)) {
      wf_abort("`id` must name a column in `data`.", "wf_error_input",
               list(id = id))
    }
    canon <- .chr(data[[id]])
  } else {
    canon <- as.character(seq_len(n))
  }
  if (anyDuplicated(canon)) {
    wf_abort("Unit ids are not unique.", "wf_error_input")
  }
  if (!is.null(base_weight)) {
    if (length(base_weight) != 1 || !is.character(base_weight) ||
        !base_weight %in% names(data)) {
      wf_abort("`base_weight` must name a column in `data`.", "wf_error_input",
               list(base_weight = base_weight))
    }
    base <- as.numeric(data[[base_weight]])
  } else {
    base <- rep(1, n)
  }
  if (any(!is.finite(base)) || any(base <= 0)) {
    wf_abort("`base_weight` must be positive and finite.", "wf_error_input")
  }

  design <- .wf_design(data, strata, clusters)
  t0 <- Sys.time()
  gen <- switch(
    method,
    bootstrap = .wf_boot_mult(design, R, seed),
    jackknife = .wf_jack_mult(design),
    brr = .wf_brr_mult(design, rho = rho)
  )

  align <- function(fit) {
    if (!inherits(fit, "wf_weights") || is.null(fit$data$id) ||
        is.null(fit$data$weight)) {
      wf_abort("`refit` must return a wf_weights with id and weight columns.",
               "wf_error_input")
    }
    fid <- .chr(fit$data$id)
    m <- match(canon, fid)
    if (length(fid) != n || anyNA(m)) {
      wf_abort("`refit` output ids do not match the input units.",
               "wf_error_input")
    }
    grp <- if (is.null(fit$data$group)) rep("all", n) else .chr(fit$data$group)[m]
    list(weight = as.numeric(fit$data$weight)[m], group = grp)
  }

  base_al <- align(refit(data, base))
  rg <- ncol(gen$mult)
  rep_results <- .wf_parallel_map(
    as.list(seq_len(rg)),
    function(r) align(refit(data, base * gen$mult[, r]))$weight,
    use_parallel = parallel,
    progress = progress,
    label = "wf_replicates"
  )
  repw <- do.call(cbind, rep_results)

  structure(list(
    base = data.frame(id = canon, group = base_al$group,
                      weight = base_al$weight, stringsAsFactors = FALSE),
    replicates = repw,
    scale = gen$scale,
    rscales = gen$rscales,
    method = method,
    rho = if (method == "brr") rho else NULL,
    design = list(strata = strata, clusters = clusters,
                  n_strata = length(design$strata), R = rg,
                  fay_rho = if (method == "brr") rho else NULL,
                  parallel_workers = attr(rep_results, "workers")),
    provenance = list(
      method = method, R = rg, seed = seed, rho = if (method == "brr") rho else NULL,
      strata = strata, clusters = clusters, base_weight = base_weight,
      parallel = isTRUE(parallel),
      parallel_workers = attr(rep_results, "workers"),
      progress = isTRUE(progress),
      created = t0, elapsed = as.numeric(Sys.time() - t0, units = "secs"),
      package_version = .wf_replicates_package_version()
    )
  ), class = "wf_replicate_weights")
}

#' Print replicate weights
#'
#' @param x A `wf_replicate_weights` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_replicate_weights <- function(x, ...) {
  method <- if (!is.null(x$rho) && x$rho > 0) {
    sprintf("%s (Fay rho %.3g)", x$method, x$rho)
  } else {
    x$method
  }
  cat(sprintf("<wf_replicate_weights>  %d unit(s); method: %s; %d replicate(s)\n",
              nrow(x$base), method, ncol(x$replicates)))
  cat(sprintf("  design: %d stratum(s); scale %.4g; elapsed %.2fs\n",
              x$design$n_strata, x$scale, x$provenance$elapsed))
  invisible(x)
}
