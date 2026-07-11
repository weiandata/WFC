#' Combine replicate weights and an estimator into a variance and CI.
#'
#' Applies the unified replication rule
#' `Var = scale * sum_r rscales_r * (theta_r - theta)^2` to any estimator, using
#' the `(scale, rscales)` stored by [wf_replicates()].
#'
#' @param replicates A `wf_replicate_weights` object.
#' @param estimator A closure `function(weights, data) -> numeric` (scalar or
#'   named vector).
#' @param data The data frame the estimator reads.
#' @param level Confidence level in `(0, 1)`.
#' @param ci Interval type: `"normal"` or (bootstrap only) `"percentile"`.
#' @return A `wf_variance_result` object.
#' @export
wf_variance <- function(replicates, estimator, data, level = 0.95,
                        ci = c("normal", "percentile")) {
  if (!inherits(replicates, "wf_replicate_weights")) {
    wf_abort("`replicates` must be a wf_replicate_weights object.",
             "wf_error_input")
  }
  if (!is.function(estimator)) {
    wf_abort("`estimator` must be a function(weights, data).", "wf_error_input")
  }
  if (length(level) != 1 || !is.finite(level) || level <= 0 || level >= 1) {
    wf_abort("`level` must be a single number in (0, 1).", "wf_error_input",
             list(level = level))
  }
  ci <- match.arg(ci)
  if (ci == "percentile" && replicates$method != "bootstrap") {
    wf_abort("`ci = 'percentile'` is only valid for bootstrap replicates.",
             "wf_error_input", list(method = replicates$method))
  }

  base_est <- estimator(replicates$base$weight, data)
  nm <- names(base_est)
  theta <- as.numeric(base_est)
  q <- length(theta)
  if (q == 0) {
    wf_abort("`estimator` returned a length-zero result.", "wf_error_input")
  }

  R <- ncol(replicates$replicates)
  tr <- matrix(NA_real_, q, R)
  for (r in seq_len(R)) {
    v <- as.numeric(estimator(replicates$replicates[, r], data))
    if (length(v) != q) {
      wf_abort("`estimator` returned inconsistent length across replicates.",
               "wf_error_input")
    }
    tr[, r] <- v
  }

  dev2 <- (tr - theta)^2
  variance <- replicates$scale * as.numeric(dev2 %*% replicates$rscales)
  se <- sqrt(variance)

  if (is.null(nm)) {
    nm <- if (q == 1) "estimate" else as.character(seq_len(q))
  }

  if (ci == "normal") {
    z <- stats::qnorm(1 - (1 - level) / 2)
    lo <- theta - z * se
    hi <- theta + z * se
  } else {
    a <- (1 - level) / 2
    lo <- vapply(seq_len(q),
                 function(i) stats::quantile(tr[i, ], a, names = FALSE),
                 numeric(1))
    hi <- vapply(seq_len(q),
                 function(i) stats::quantile(tr[i, ], 1 - a, names = FALSE),
                 numeric(1))
  }

  structure(list(
    table = data.frame(
      quantity = nm, estimate = theta, variance = variance, se = se,
      ci_lower = lo, ci_upper = hi, stringsAsFactors = FALSE
    ),
    provenance = list(method = replicates$method, level = level,
                      ci = ci, R = R)
  ), class = "wf_variance_result")
}

#' Print a variance result
#'
#' @param x A `wf_variance_result` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_variance_result <- function(x, ...) {
  cat(sprintf("<wf_variance_result>  method: %s; %d replicate(s); %.0f%% %s CI\n",
              x$provenance$method, x$provenance$R,
              100 * x$provenance$level, x$provenance$ci))
  print(x$table, row.names = FALSE)
  invisible(x)
}

#' Coerce a variance result to a data frame
#'
#' @param x A `wf_variance_result` object.
#' @param ... Unused.
#' @return The result table as a data frame.
#' @export
as.data.frame.wf_variance_result <- function(x, ...) {
  x$table
}
