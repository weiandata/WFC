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

#' Target from a manual margin table
#'
#' Builds a canonical `wf_target` from a ready-made long margin table with one
#' row per group, dimension, and category.
#'
#' @param margins Data frame containing margin values.
#' @param dims A `wf_dims` object.
#' @param dim_col Column containing dimension names.
#' @param cat_col Column containing category names.
#' @param value_col Column containing non-negative margin values.
#' @param by Optional target grouping variable.
#' @param group_col Column containing group keys. Defaults to `by`.
#' @param totals Optional named numeric vector of group totals.
#' @param mode Target mode label.
#'
#' @return A `wf_target` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(gender = c("female", "male"))
#' margins <- data.frame(
#'   dimension = c("gender", "gender"),
#'   category = c("female", "male"),
#'   value = c(55, 45)
#' )
#' wf_target_manual(margins, dims)
wf_target_manual <- function(margins, dims,
                             dim_col = "dimension",
                             cat_col = "category",
                             value_col = "value",
                             by = NULL, group_col = by,
                             totals = NULL, mode = "manual") {
  if (!is.data.frame(margins)) {
    wf_abort("`margins` must be a data.frame.", "wf_error_input")
  }
  if (!inherits(dims, "wf_dims")) {
    wf_abort("`dims` must be a wf_dims object.", "wf_error_input")
  }
  dvars <- names(dims$vars)
  .require_cols(margins, c(dim_col, cat_col, value_col, group_col), "manual margins")

  vals <- margins[[value_col]]
  if (any(is.na(vals)) || any(!is.finite(vals)) || any(vals < 0)) {
    wf_abort("Manual margin values must be finite and >= 0.", "wf_error_input")
  }

  gkey <- if (is.null(by)) rep("_all_", nrow(margins)) else .chr(margins[[group_col]])
  dims_in <- unique(.chr(margins[[dim_col]]))
  missing_dims <- setdiff(dvars, dims_in)
  extra_dims <- setdiff(dims_in, dvars)
  if (length(missing_dims) > 0 || length(extra_dims) > 0) {
    wf_abort(
      sprintf(
        "Manual margins must contain exactly the target dimensions. Missing: %s; extra: %s.",
        paste(missing_dims, collapse = ", "),
        paste(extra_dims, collapse = ", ")
      ),
      "wf_error_schema",
      list(missing = missing_dims, extra = extra_dims)
    )
  }

  groups <- list()
  for (g in sort(unique(gkey))) {
    sel_g <- gkey == g
    group_margins <- list()
    dim_totals <- numeric(length(dvars))
    names(dim_totals) <- dvars
    for (d in dvars) {
      sel_d <- sel_g & .chr(margins[[dim_col]]) == d
      cats <- .chr(margins[[cat_col]][sel_d])
      values <- margins[[value_col]][sel_d]
      agg <- tapply(values, cats, sum)
      agg <- .wf_margin_vector(agg[agg > 0])
      level_order <- dims$vars[[d]]
      if (!is.null(level_order)) {
        agg <- agg[c(intersect(level_order, names(agg)), setdiff(names(agg), level_order))]
      }
      if (is.null(agg) || length(agg) == 0) {
        wf_abort(sprintf("Group '%s', dim '%s': no positive manual margins.", g, d), "wf_error_input")
      }
      group_margins[[d]] <- agg
      dim_totals[[d]] <- sum(agg)
    }
    total <- if (is.null(totals)) {
      dim_totals[[1]]
    } else {
      if (is.null(names(totals)) || is.na(totals[g])) {
        wf_abort(sprintf("`totals` must include group '%s'.", g), "wf_error_input")
      }
      unname(totals[g])
    }
    groups[[g]] <- list(total = total, margins = group_margins)
  }

  .wf_new_target(
    mode,
    by,
    dvars,
    groups,
    meta = list(scale = "manual", created = Sys.time())
  )
}

#' Shrink a target toward a reference target
#'
#' Blends each selected target group's margin shares with reference shares while
#' preserving the local target group totals.
#'
#' @param target Local `wf_target` object.
#' @param reference Reference `wf_target` object. A single reference group is
#'   applied to all selected target groups.
#' @param lambda Local-share weight in `[0, 1]`. Smaller values shrink more
#'   strongly toward `reference`.
#' @param groups Optional target groups to shrink.
#'
#' @return A `wf_target` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(gender = c("female", "male"))
#' local <- wf_target_manual(
#'   data.frame(dimension = c("gender", "gender"),
#'              category = c("female", "male"),
#'              value = c(80, 20)),
#'   dims
#' )
#' reference <- wf_target_manual(
#'   data.frame(dimension = c("gender", "gender"),
#'              category = c("female", "male"),
#'              value = c(50, 50)),
#'   dims
#' )
#' wf_target_shrink(local, reference, lambda = 0.25)
wf_target_shrink <- function(target, reference, lambda, groups = NULL) {
  if (!inherits(target, "wf_target") || !inherits(reference, "wf_target")) {
    wf_abort("`target` and `reference` must be wf_target objects.", "wf_error_input")
  }
  if (length(lambda) != 1 || !is.finite(lambda) || lambda < 0 || lambda > 1) {
    wf_abort("`lambda` must be a single number in [0, 1].", "wf_error_input")
  }
  if (!identical(target$dims, reference$dims)) {
    wf_abort("`target` and `reference` must have identical dimensions.", "wf_error_schema")
  }
  groups <- if (is.null(groups)) names(target$groups) else .chr(groups)
  ref_single <- length(reference$groups) == 1
  ref_one <- reference$groups[[1]]
  out <- target

  for (g in groups) {
    if (is.null(out$groups[[g]])) {
      wf_abort(sprintf("Unknown target group '%s'.", g), "wf_error_input", list(group = g))
    }
    ref_group <- if (ref_single) ref_one else reference$groups[[g]]
    if (is.null(ref_group)) {
      wf_abort(sprintf("Reference target has no group '%s'.", g), "wf_error_schema", list(group = g))
    }
    for (d in out$dims) {
      local_m <- out$groups[[g]]$margins[[d]]
      ref_m <- ref_group$margins[[d]]
      if (!identical(sort(names(local_m)), sort(names(ref_m)))) {
        wf_abort(
          sprintf("Group '%s', dim '%s': target and reference categories differ.", g, d),
          "wf_error_schema",
          list(group = g, dim = d)
        )
      }
      ref_m <- ref_m[names(local_m)]
      local_share <- local_m / sum(local_m)
      ref_share <- ref_m / sum(ref_m)
      new_share <- lambda * local_share + (1 - lambda) * ref_share
      out$groups[[g]]$margins[[d]] <- .wf_margin_vector(out$groups[[g]]$total * new_share)
    }
  }
  out$meta$shrinkage <- c(out$meta$shrinkage, list(list(
    lambda = lambda,
    groups = groups,
    reference_mode = reference$mode,
    created = Sys.time()
  )))
  .wf_validate_target(out)
  out
}
