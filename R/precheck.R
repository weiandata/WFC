#' Create a structured precheck issue.
#'
#' @param group Group key.
#' @param dim Dimension name.
#' @param category Category key.
#' @param check Check identifier.
#' @param severity Issue severity.
#' @param detail Human-readable detail.
#' @keywords internal
#' @noRd
.wf_issue <- function(group, dim, category, check, severity, detail) {
  data.frame(
    group = group,
    dim = dim,
    category = category,
    check = check,
    severity = severity,
    detail = detail,
    stringsAsFactors = FALSE
  )
}

#' Precheck sample and target compatibility
#'
#' Runs structural feasibility checks before weighting.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param id Optional unique unit identifier column.
#' @param na Missing calibration data policy.
#' @param max_na_dims Maximum allowed missing calibration dimensions per row.
#' @param thin_min Minimum unweighted support before warning.
#' @param risk_ratio Target/sample share ratio warning threshold.
#'
#' @return A `wf_precheck` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(gender = c("female", "male"))
#' pop <- data.frame(gender = c("female", "male"), count = c(55, 45))
#' target <- wf_target_population(pop, c(gender = "gender"), "count", dims)
#' sample <- data.frame(id = 1:4, gender = c("female", "male", "female", "male"))
#' wf_precheck(sample, target, id = "id")
wf_precheck <- function(sample, target, id = NULL,
                        na = c("fractional", "drop", "error"),
                        max_na_dims = 2, thin_min = 5, risk_ratio = 10) {
  na <- match.arg(na)
  iss <- list()
  dvars <- target$dims

  miss <- setdiff(c(dvars, target$by), names(sample))
  if (length(miss) > 0) {
    iss[[length(iss) + 1]] <- .wf_issue(
      "*",
      paste(miss, collapse = ","),
      NA,
      "schema_missing_var",
      "error",
      sprintf("Sample is missing variable(s): %s", paste(miss, collapse = ", "))
    )
    out <- do.call(rbind, iss)
    return(structure(list(issues = out, ok = FALSE, na = na), class = "wf_precheck"))
  }

  if (!is.null(id)) {
    dup <- sum(duplicated(sample[[id]]))
    if (dup > 0) {
      iss[[length(iss) + 1]] <- .wf_issue(
        "*",
        NA,
        NA,
        "dup_id",
        "error",
        sprintf("%d duplicated value(s) in id column '%s'.", dup, id)
      )
    }
  }

  gkey <- .wf_group_keys(sample, target$by)
  if (!is.null(target$by) && any(is.na(sample[[target$by]]))) {
    iss[[length(iss) + 1]] <- .wf_issue(
      "*",
      target$by,
      NA,
      "na_group",
      "error",
      sprintf(
        "%d row(s) have NA in grouping variable '%s'.",
        sum(is.na(sample[[target$by]])),
        target$by
      )
    )
  }

  sample_groups <- unique(gkey[!is.na(gkey)])
  s_only <- setdiff(sample_groups, names(target$groups))
  t_only <- setdiff(names(target$groups), sample_groups)
  if (length(s_only) > 0) {
    iss[[length(iss) + 1]] <- .wf_issue(
      "*",
      target$by,
      NA,
      "group_unmatched",
      "error",
      sprintf("Group(s) in sample but not in target: %s", paste(s_only, collapse = ", "))
    )
  }
  if (length(t_only) > 0) {
    iss[[length(iss) + 1]] <- .wf_issue(
      "*",
      target$by,
      NA,
      "group_unmatched",
      "warning",
      sprintf(
        "Group(s) in target but not in sample (ignored): %s",
        paste(t_only, collapse = ", ")
      )
    )
  }

  na_mat <- sapply(dvars, function(d) is.na(sample[[d]]))
  if (is.null(dim(na_mat))) {
    na_mat <- matrix(na_mat, nrow = nrow(sample))
  }
  n_na_dims <- rowSums(na_mat)
  over <- which(n_na_dims > max_na_dims)
  if (length(over) > 0) {
    iss[[length(iss) + 1]] <- .wf_issue(
      "*",
      NA,
      NA,
      "na_overload",
      "error",
      sprintf(
        "%d row(s) have NA in more than %d dimensions (first rows: %s).",
        length(over),
        max_na_dims,
        paste(utils::head(over, 5), collapse = ", ")
      )
    )
  }
  if (na == "error" && any(n_na_dims > 0)) {
    iss[[length(iss) + 1]] <- .wf_issue(
      "*",
      NA,
      NA,
      "na_load",
      "error",
      sprintf(
        "na='error': %d row(s) contain NA in calibration dimensions.",
        sum(n_na_dims > 0)
      )
    )
  }

  for (g in intersect(names(target$groups), sample_groups)) {
    sel <- !is.na(gkey) & gkey == g
    n_g <- sum(sel)
    for (d in dvars) {
      v <- .chr(sample[[d]][sel])
      is_na <- is.na(sample[[d]][sel])
      n_na_d <- sum(is_na)
      tg <- target$groups[[g]]$margins[[d]]
      share_t <- tg / sum(tg)
      cnt <- table(v[!is_na])

      unk <- setdiff(names(cnt), names(tg))
      if (length(unk) > 0) {
        iss[[length(iss) + 1]] <- .wf_issue(
          g,
          d,
          paste(unk, collapse = ","),
          "cat_unknown_in_sample",
          "error",
          sprintf(
            "Categories in sample with no target share: %s (%d row(s)). Collapse or recode.",
            paste(unk, collapse = ", "),
            sum(cnt[unk])
          )
        )
      }

      for (k in names(tg)) {
        n_k <- if (k %in% names(cnt)) cnt[[k]] else 0L
        eff_support <- n_k + if (na == "fractional") n_na_d else 0L
        if (eff_support == 0) {
          iss[[length(iss) + 1]] <- .wf_issue(
            g,
            d,
            k,
            "cat_infeasible",
            "error",
            sprintf(
              "Target share %.1f%% but zero sample support. IPF cannot converge; collapse this category.",
              100 * share_t[[k]]
            )
          )
        } else if (n_k < thin_min && share_t[[k]] > 0.01) {
          iss[[length(iss) + 1]] <- .wf_issue(
            g,
            d,
            k,
            "support_thin",
            "warning",
            sprintf("Only %d respondent(s) for a %.1f%% target share.", n_k, 100 * share_t[[k]])
          )
        }
        if (n_k > 0) {
          ratio <- share_t[[k]] / (n_k / max(n_g - n_na_d, 1))
          if (ratio > risk_ratio) {
            iss[[length(iss) + 1]] <- .wf_issue(
              g,
              d,
              k,
              "risk_extreme_ratio",
              "warning",
              sprintf(
                "Target/sample share ratio %.1f: expect weights ~%.0fx the mean; consider collapsing.",
                ratio,
                ratio
              )
            )
          }
        }
      }
      if (n_na_d > 0) {
        iss[[length(iss) + 1]] <- .wf_issue(
          g,
          d,
          NA,
          "na_load",
          "note",
          sprintf("%d row(s) (%.1f%%) NA on this dimension; policy: %s.", n_na_d, 100 * n_na_d / n_g, na)
        )
      }
    }
  }

  issues <- if (length(iss) > 0) {
    do.call(rbind, iss)
  } else {
    .wf_issue(character(0), character(0), character(0), character(0), character(0), character(0))
  }
  structure(
    list(issues = issues, ok = !any(issues$severity == "error"), na = na),
    class = "wf_precheck"
  )
}

#' Print a precheck result
#'
#' @param x A `wf_precheck` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_precheck <- function(x, ...) {
  cat(sprintf(
    "<wf_precheck>  verdict: %s\n",
    if (x$ok) "OK - no blocking issues" else "BLOCKED"
  ))
  if (nrow(x$issues) == 0) {
    cat("  no issues found\n")
    return(invisible(x))
  }
  tab <- table(x$issues$severity)
  cat(sprintf("  %s\n", paste(sprintf("%s: %d", names(tab), tab), collapse = " | ")))
  ord <- order(match(x$issues$severity, c("error", "warning", "note")))
  show <- utils::head(x$issues[ord, ], 20)
  for (i in seq_len(nrow(show))) {
    cat(sprintf(
      "  [%s] %s / %s%s -- %s\n",
      show$severity[i],
      show$group[i],
      show$dim[i],
      ifelse(is.na(show$category[i]), "", paste0(":", show$category[i])),
      show$detail[i]
    ))
  }
  if (nrow(x$issues) > 20) {
    cat(sprintf("  ... and %d more (see $issues)\n", nrow(x$issues) - 20))
  }
  invisible(x)
}
