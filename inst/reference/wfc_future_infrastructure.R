# ============================================================================
# WFC Extension 3 -- reference implementation, part 2 of 3 (releases 0.12-0.13)
# Ecosystem interoperability and production pipeline infrastructure.
#
# Prototype code: source AFTER library(WFC). Soft dependencies (survey) are
# checked with requireNamespace(); the core stays base-R (design commitment).
#
# Contents:
#   1. as_svydesign() / as_svrepdesign()  -- survey bridges     [design §5.1]
#   2. augment / tidy / glance            -- broom-style        [design §5.2]
#   3. wf_pipeline() / wf_run()           -- declarative chain  [design §6.1]
#   4. wf_validate()                      -- weight drift check [design §6.2]
#   5. wf_audit_export()                  -- JSON audit trail   [design §6.3]
# ============================================================================

# ----------------------------------------------------------------------------
# 1. survey bridges -----------------------------------------------------------
# ----------------------------------------------------------------------------

#' wf_weights -> survey::svydesign (weights joined onto `data` by id).
as_svydesign <- function(w, data, id = "id") {
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("as_svydesign() needs the 'survey' package: install.packages(\"survey\")")
  }
  stopifnot(inherits(w, "wf_weights"))
  key <- trimws(as.character(data[[id]]))
  m <- match(key, trimws(as.character(w$data$id)))
  if (anyNA(m)) stop(sprintf("%d row(s) of `data` have no weight (unmatched id).", sum(is.na(m))))
  data$.wf_weight <- w$data$weight[m]
  survey::svydesign(ids = ~1, weights = ~.wf_weight, data = data)
}

#' wf_replicate_weights -> survey::svrepdesign. The stored (scale, rscales)
#' map directly onto svrepdesign's unified combining rule, so svymean/svyglm
#' reproduce wf_variance() exactly.
as_svrepdesign <- function(r, data, id = "id") {
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("as_svrepdesign() needs the 'survey' package: install.packages(\"survey\")")
  }
  stopifnot(inherits(r, "wf_replicate_weights"))
  key <- trimws(as.character(data[[id]]))
  m <- match(key, r$base$id)
  if (anyNA(m)) stop(sprintf("%d row(s) of `data` have no replicate weights.", sum(is.na(m))))
  survey::svrepdesign(
    data = data,
    weights = r$base$weight[m],
    repweights = r$replicates[m, , drop = FALSE],
    type = "other",
    scale = r$scale,
    rscales = r$rscales,
    combined.weights = TRUE
  )
}

# ----------------------------------------------------------------------------
# 2. broom-style tidiers ------------------------------------------------------
# In the package these register as S3 methods conditionally on `generics`.
# ----------------------------------------------------------------------------

#' Join calibrated weights back onto the input sample by id.
augment.wf_weights <- function(x, data, id = "id", ...) {
  key <- trimws(as.character(data[[id]]))
  m <- match(key, trimws(as.character(x$data$id)))
  data$.weight <- x$data$weight[m]
  data$.feature <- x$data$feature[m]
  data
}

tidy.wf_diagnostics <- function(x, ...) x$table

tidy.wf_variance_result <- function(x, ...) x$table

glance.wf_weights <- function(x, ...) {
  wt <- x$data$weight
  data.frame(
    n = nrow(x$data),
    groups = nrow(x$log),
    total_weight = sum(wt),
    ess = sum(wt)^2 / sum(wt^2),
    deff = 1 + (stats::sd(wt) / mean(wt))^2,
    method = if (is.null(x$provenance$method)) "raking" else x$provenance$method,
    stringsAsFactors = FALSE
  )
}

# ----------------------------------------------------------------------------
# 3. wf_pipeline() / wf_run() -------------------------------------------------
# A weighting round as a serializable spec: plain lists in, wf_weights out.
# wf_run(spec, ...) is also a valid `refit` closure body for wf_replicates().
# ----------------------------------------------------------------------------

wf_pipeline <- function(target, stages, validate = NULL) {
  stopifnot(is.list(target), is.list(stages))
  allowed <- c("propensity", "calibrate")
  bad <- setdiff(names(stages), allowed)
  if (length(bad) > 0) {
    stop(sprintf("Unknown pipeline stage(s): %s. Supported: %s.",
                 paste(bad, collapse = ", "), paste(allowed, collapse = ", ")))
  }
  spec <- list(target = target, stages = stages, validate = validate,
               created = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  spec$hash <- .wf_spec_hash(spec[c("target", "stages", "validate")])
  structure(spec, class = "wf_pipeline")
}

# Dependency-free content hash (djb2 over the deparsed spec); the packaged
# version may use tools::md5sum on a serialized tempfile instead.
.wf_spec_hash <- function(x) {
  s <- paste(deparse(x), collapse = "")
  h <- 5381
  for (ch in utf8ToInt(s)) h <- (h * 33 + ch) %% 2^31
  sprintf("%08x", h)
}

wf_run <- function(spec, sample, dims, population = NULL, reference = NULL,
                   base_weight = NULL) {
  stopifnot(inherits(spec, "wf_pipeline"))

  # -- target -----------------------------------------------------------------
  tg <- spec$target
  target <- if (identical(tg$mode, "population")) {
    if (is.null(population)) stop("Pipeline target mode 'population' needs `population`.")
    do.call(wf_target_population,
            c(list(pop = population, key_map = tg$key_map, count = tg$count,
                   dims = dims), tg[setdiff(names(tg), c("mode", "key_map", "count"))]))
  } else if (identical(tg$mode, "reference")) {
    if (is.null(reference)) stop("Pipeline target mode 'reference' needs `reference`.")
    do.call(wf_target_reference,
            c(list(ref = reference, feature = tg$feature, dims = dims),
              tg[setdiff(names(tg), c("mode", "feature"))]))
  } else {
    stop(sprintf("Unsupported pipeline target mode '%s'.", tg$mode))
  }

  # -- stage 1: propensity (optional) ------------------------------------------
  init_col <- base_weight
  work <- sample
  stage1 <- NULL
  if (!is.null(spec$stages$propensity)) {
    if (is.null(reference)) stop("Pipeline stage 'propensity' needs `reference`.")
    ps <- spec$stages$propensity
    pt <- wf_target_propensity(sample, reference, ps$formula,
                               by = ps$by, id = ps$id)
    stage1 <- do.call(wf_propensity,
                      c(list(target = pt), ps[setdiff(names(ps), c("formula", "by", "id"))]))
    sid <- trimws(as.character(stage1$data$id))
    key <- if (is.null(ps$id)) as.character(seq_len(nrow(work)))
           else trimws(as.character(work[[ps$id]]))
    m <- match(key, sid)
    if (anyNA(m)) stop("Propensity stage ids do not match the sample rows.")
    work$.wf_stage1 <- stage1$data$weight[m]
    init_col <- ".wf_stage1"
  }

  # -- stage 2: calibrate -------------------------------------------------------
  cal <- spec$stages$calibrate
  if (is.null(cal)) stop("Pipeline must contain a 'calibrate' stage.")
  args <- c(list(sample = work, target = target), cal)
  if (!is.null(init_col)) args$init_weight <- init_col
  w <- do.call(wf_calibrate, args)
  w$provenance$pipeline_hash <- spec$hash

  # -- declared validation ------------------------------------------------------
  if (!is.null(spec$validate)) {
    d <- wf_diagnose(w, target = target)$table
    v <- spec$validate
    if (!is.null(v$max_deff) && any(d$deff > v$max_deff)) {
      warning(sprintf("Pipeline validation: %d group(s) exceed max_deff = %g.",
                      sum(d$deff > v$max_deff), v$max_deff))
    }
    if (!is.null(v$max_margin_dev) && "margin_maxerr" %in% names(d) &&
        any(d$margin_maxerr > v$max_margin_dev, na.rm = TRUE)) {
      warning(sprintf("Pipeline validation: margin deviation exceeds %g.",
                      v$max_margin_dev))
    }
  }
  w
}

# ----------------------------------------------------------------------------
# 4. wf_validate() -- weight drift detection ----------------------------------
# "Did this round's weights silently change character?" Compares a new
# wf_weights against a reference release on group coverage, deff/ESS deltas,
# and the per-unit weight-ratio distribution where ids overlap.
# ----------------------------------------------------------------------------

wf_validate <- function(new, reference,
                        max_deff_delta = 1.0,
                        max_ratio_p99 = 2.0,
                        max_total_shift = 0.05) {
  stopifnot(inherits(new, "wf_weights"), inherits(reference, "wf_weights"))
  gstat <- function(w) {
    parts <- split(w$data$weight, w$data$group)
    data.frame(
      group = names(parts),
      n = vapply(parts, length, integer(1)),
      total = vapply(parts, sum, numeric(1)),
      deff = vapply(parts, function(x) 1 + (stats::sd(x) / mean(x))^2, numeric(1)),
      stringsAsFactors = FALSE, row.names = NULL
    )
  }
  a <- gstat(new); b <- gstat(reference)
  cmp <- merge(a, b, by = "group", suffixes = c("_new", "_ref"), all = TRUE)
  cmp$deff_delta <- cmp$deff_new - cmp$deff_ref
  cmp$total_shift <- abs(cmp$total_new - cmp$total_ref) / cmp$total_ref

  issues <- character(0)
  gone <- cmp$group[is.na(cmp$n_new)]
  born <- cmp$group[is.na(cmp$n_ref)]
  if (length(gone) > 0) issues <- c(issues, sprintf("groups missing in new: %s", paste(gone, collapse = ", ")))
  if (length(born) > 0) issues <- c(issues, sprintf("new groups appeared: %s", paste(born, collapse = ", ")))
  hit <- !is.na(cmp$deff_delta) & cmp$deff_delta > max_deff_delta
  if (any(hit)) issues <- c(issues, sprintf("deff rose by more than %g in: %s",
                                            max_deff_delta, paste(cmp$group[hit], collapse = ", ")))
  hit <- !is.na(cmp$total_shift) & cmp$total_shift > max_total_shift
  if (any(hit)) issues <- c(issues, sprintf("group total shifted by more than %.0f%% in: %s",
                                            100 * max_total_shift, paste(cmp$group[hit], collapse = ", ")))

  ratio <- NULL
  ids_new <- trimws(as.character(new$data$id))
  ids_ref <- trimws(as.character(reference$data$id))
  common <- intersect(ids_new, ids_ref)
  if (length(common) > 10) {
    r <- new$data$weight[match(common, ids_new)] /
         reference$data$weight[match(common, ids_ref)]
    r <- r / stats::median(r)                       # remove pure rescaling
    p99 <- stats::quantile(r, 0.99, names = FALSE)
    p01 <- stats::quantile(r, 0.01, names = FALSE)
    ratio <- list(n_common = length(common), p01 = p01, median = 1, p99 = p99)
    if (p99 > max_ratio_p99 || p01 < 1 / max_ratio_p99) {
      issues <- c(issues, sprintf(
        "per-unit weight ratios drifted: 1%%/99%% quantiles %.2f / %.2f (threshold %gx)",
        p01, p99, max_ratio_p99))
    }
  }

  ok <- length(issues) == 0
  if (!ok) warning(paste("wf_validate:", paste(issues, collapse = "; ")))
  structure(list(ok = ok, issues = issues, comparison = cmp, ratio = ratio,
                 thresholds = list(max_deff_delta = max_deff_delta,
                                   max_ratio_p99 = max_ratio_p99,
                                   max_total_shift = max_total_shift)),
            class = "wf_validation")
}

print.wf_validation <- function(x, ...) {
  cat(sprintf("<wf_validation>  %s\n", if (x$ok) "PASS - no drift detected" else "DRIFT DETECTED"))
  for (i in x$issues) cat("  -", i, "\n")
  invisible(x)
}

# ----------------------------------------------------------------------------
# 5. wf_audit_export() -- provenance as a self-contained JSON file -------------
# Base-R JSON serializer (no jsonlite): lists -> objects, unnamed lists and
# length>1 vectors -> arrays, data frames -> arrays of row objects.
# ----------------------------------------------------------------------------

.wf_json <- function(x) {
  esc <- function(s) {
    s <- gsub("\\", "\\\\", s, fixed = TRUE)
    s <- gsub("\"", "\\\"", s, fixed = TRUE)
    s <- gsub("\n", "\\n", s, fixed = TRUE)
    s <- gsub("\r", "\\r", s, fixed = TRUE)
    s <- gsub("\t", "\\t", s, fixed = TRUE)
    s
  }
  scalar <- function(v) {
    if (is.na(v)) return("null")
    if (is.logical(v)) return(if (v) "true" else "false")
    if (is.numeric(v)) return(format(v, digits = 15, scientific = FALSE, trim = TRUE))
    paste0("\"", esc(as.character(v)), "\"")
  }
  if (is.null(x)) return("null")
  if (inherits(x, "POSIXt")) x <- format(x, "%Y-%m-%dT%H:%M:%S%z")
  if (is.function(x)) return("\"<function>\"")
  if (is.factor(x)) x <- as.character(x)
  if (is.data.frame(x)) {
    rows <- lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
    return(paste0("[", paste(vapply(rows, .wf_json, ""), collapse = ","), "]"))
  }
  if (is.list(x)) {
    nm <- names(x)
    if (!is.null(nm) && all(nzchar(nm))) {
      items <- vapply(seq_along(x), function(i) {
        paste0("\"", esc(nm[i]), "\":", .wf_json(x[[i]]))
      }, "")
      return(paste0("{", paste(items, collapse = ","), "}"))
    }
    return(paste0("[", paste(vapply(x, .wf_json, ""), collapse = ","), "]"))
  }
  if (length(x) == 1) return(scalar(x))
  paste0("[", paste(vapply(x, scalar, ""), collapse = ","), "]")
}

wf_audit_export <- function(w, file, extra = NULL) {
  stopifnot(inherits(w, "wf_weights") || inherits(w, "wf_autoweigh_result"))
  ledger <- NULL
  if (inherits(w, "wf_autoweigh_result")) {
    ledger <- lapply(w$ledger, function(e) e[c("step", "action", "detail", "time")])
    w <- w$weights
  }
  payload <- list(
    exported = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    n_units = nrow(w$data),
    weight_sum = sum(w$data$weight),
    groups = unique(w$data$group),
    provenance = w$provenance,
    decision_ledger = ledger,
    extra = extra
  )
  writeLines(.wf_json(payload), file, useBytes = TRUE)
  invisible(file)
}
