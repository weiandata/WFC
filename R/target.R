#' Target from external population data
#'
#' Converts arbitrary population data to a canonical `wf_target` object.
#'
#' @param pop Population data frame.
#' @param key_map Named character vector mapping `wf_dims` dimensions to population columns.
#' @param count Population count column.
#' @param dims A `wf_dims` object.
#' @param by Optional grouping variable.
#' @param by_key Optional group key column name or function.
#' @param scale Target scale, one of `"population"`, `"sample"`, or `"custom"`.
#' @param sample Required when `scale = "sample"`.
#' @param totals Required when `scale = "custom"`.
#' @param keep_joint Whether to retain per-group joint population cells.
#'
#' @return A `wf_target` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(gender = c("female", "male"))
#' pop <- data.frame(gender = c("female", "male"), count = c(55, 45))
#' wf_target_population(pop, c(gender = "gender"), "count", dims)
wf_target_population <- function(pop, key_map, count, dims,
                                 by = NULL, by_key = NULL,
                                 scale = c("population", "sample", "custom"),
                                 sample = NULL, totals = NULL,
                                 keep_joint = FALSE) {
  scale <- match.arg(scale)
  if (!is.data.frame(pop)) {
    wf_abort("`pop` must be a data.frame.", "wf_error_input")
  }
  dvars <- names(dims$vars)
  if (is.null(names(key_map)) || !setequal(names(key_map), dvars)) {
    wf_abort(
      "`key_map` must be a named vector mapping every wf_dims dimension to a population column.",
      "wf_error_schema",
      list(expected = dvars, got = names(key_map))
    )
  }
  .require_cols(pop, unname(key_map), "population data")
  .require_cols(pop, count, "population data")

  cnt <- pop[[count]]
  if (any(is.na(cnt))) {
    wf_abort(sprintf(
      "Population count column '%s' has %d NA value(s).",
      count,
      sum(is.na(cnt))
    ), "wf_error_input")
  }
  if (any(cnt < 0)) {
    wf_abort(sprintf(
      "Population count column '%s' has negative values.",
      count
    ), "wf_error_input")
  }

  gkey <- .wf_group_keys(pop, by, by_key)
  groups <- list()
  joint <- if (keep_joint) list() else NULL
  for (g in sort(unique(gkey))) {
    sel <- gkey == g
    margins <- list()
    for (d in dvars) {
      v <- .chr(pop[[key_map[[d]]]][sel])
      m <- tapply(cnt[sel], v, sum)
      margins[[d]] <- .wf_margin_vector(m[m > 0])
    }
    groups[[g]] <- list(total = sum(cnt[sel]), margins = margins)

    if (keep_joint) {
      j <- data.frame(
        lapply(dvars, function(d) .chr(pop[[key_map[[d]]]][sel])),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
      names(j) <- dvars
      j$pop <- cnt[sel]
      j <- stats::aggregate(j["pop"], j[dvars], sum)
      joint[[g]] <- j[j$pop > 0, c(dvars, "pop"), drop = FALSE]
    }
  }

  sample_n <- NULL
  if (scale == "sample") {
    if (is.null(sample)) {
      wf_abort("scale='sample' requires `sample`.", "wf_error_input")
    }
    sample_n <- table(.wf_group_keys(sample, by))
    sample_n <- stats::setNames(as.numeric(sample_n), names(sample_n))
  }
  groups <- .wf_scale_groups(groups, scale, sample_n, totals)
  if (keep_joint) {
    for (g in names(joint)) {
      f <- groups[[g]]$total / sum(joint[[g]]$pop)
      joint[[g]]$pop <- joint[[g]]$pop * f
    }
  }

  .wf_new_target(
    "population",
    by,
    dvars,
    groups,
    meta = list(scale = scale, created = Sys.time()),
    joint = joint
  )
}

#' Target from a weighted reference sample
#'
#' Builds a canonical `wf_target` from a reference sample where `feature` is the
#' reciprocal of the design weight.
#'
#' @param ref Reference sample data frame.
#' @param feature Feature value column equal to `1 / design_weight`.
#' @param dims A `wf_dims` object.
#' @param by Optional grouping variable.
#' @param feature_na Policy for missing feature values.
#' @param feature_gt1 Policy for feature values greater than one.
#'
#' @return A `wf_target` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(gender = c("female", "male"))
#' ref <- data.frame(gender = c("female", "male"), feature = c(0.5, 0.25))
#' wf_target_reference(ref, "feature", dims)
wf_target_reference <- function(ref, feature, dims, by = NULL,
                                feature_na = c("error", "drop"),
                                feature_gt1 = c("warn", "allow")) {
  feature_na <- match.arg(feature_na)
  feature_gt1 <- match.arg(feature_gt1)
  dvars <- names(dims$vars)
  .require_cols(ref, c(dvars, feature, by), "reference sample")

  f <- ref[[feature]]
  bad_na <- which(is.na(f))
  if (length(bad_na) > 0) {
    msg <- sprintf(
      "%d of %d reference rows (%.1f%%) have missing feature values.",
      length(bad_na),
      nrow(ref),
      100 * length(bad_na) / nrow(ref)
    )
    if (feature_na == "error") {
      wf_abort(
        paste(msg, "Use feature_na='drop' to exclude them from target construction."),
        "wf_error_input",
        list(rows = bad_na)
      )
    }
    wf_warn(
      paste(msg, "Dropped from target construction."),
      "wf_warning_data",
      list(rows = bad_na)
    )
    ref <- ref[-bad_na, , drop = FALSE]
    f <- ref[[feature]]
  }
  bad <- which(!is.finite(f) | f <= 0)
  if (length(bad) > 0) {
    wf_abort(sprintf(
      "Feature values must be finite and > 0; %d row(s) violate this (first: %s).",
      length(bad),
      paste(utils::head(bad, 5), collapse = ", ")
    ), "wf_error_input", list(rows = bad))
  }
  if (any(f > 1) && feature_gt1 == "warn") {
    wf_warn(sprintf(
      "%d feature value(s) exceed 1; inclusion probabilities should lie in (0,1]. Is this column a weight rather than its reciprocal?",
      sum(f > 1)
    ), "wf_warning_data")
  }

  w <- 1 / f
  gkey <- .wf_group_keys(ref, by)
  groups <- list()
  for (g in sort(unique(gkey))) {
    sel <- gkey == g
    margins <- lapply(dvars, function(d) {
      v <- .chr(ref[[d]][sel])
      if (any(is.na(ref[[d]][sel]))) {
        wf_abort(sprintf(
          "Reference sample: NA in dimension '%s' (group '%s'). Clean or drop these rows before target construction.",
          d,
          g
        ), "wf_error_input", list(group = g, dim = d))
      }
      m <- tapply(w[sel], v, sum)
      .wf_margin_vector(m[m > 0])
    })
    names(margins) <- dvars
    groups[[g]] <- list(total = sum(w[sel]), margins = margins)
  }
  .wf_new_target("reference", by, dvars, groups, meta = list(created = Sys.time()))
}
