#' Plan post-stratification cell resolution
#'
#' Resolves each population joint cell to the finest supported collapse-ladder
#' level without computing weights. Review this plan before running
#' `wf_poststrat()`.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object built with `keep_joint = TRUE`.
#' @param min_cell Minimum sample count per resolved cell.
#' @param ladder A `wf_collapse_ladder` object.
#' @param granularity Resolution strategy, either `"adaptive"` or `"province"`.
#' @param empty_cell Empty-cell policy, one of `"redistribute"`, `"flag"`, or
#'   `"error"`.
#' @param id Reserved for future plan-level row diagnostics.
#'
#' @return A `wf_poststrat_plan` object.
#' @export
wf_plan_poststrat <- function(sample, target, min_cell, ladder,
                              granularity = c("adaptive", "province"),
                              empty_cell = c("redistribute", "flag", "error"),
                              id = NULL) {
  granularity <- match.arg(granularity)
  empty_cell <- match.arg(empty_cell)
  .wf_check_poststrat_args(sample, target, min_cell, ladder)

  dvars <- target$dims
  gkey <- .wf_group_keys(sample, target$by)
  plan_rows <- list()
  diag_rows <- list()

  for (g in intersect(names(target$joint), unique(gkey))) {
    sel <- gkey == g
    smat <- as.matrix(sapply(dvars, function(d) .chr(sample[[d]][sel])))
    if (is.null(dim(smat))) {
      smat <- matrix(smat, ncol = length(dvars), dimnames = list(NULL, dvars))
    }
    jdf <- target$joint[[g]]
    res <- .wf_resolve_group(smat, jdf, dvars, ladder, min_cell, granularity, g)
    if (any(res$orphan) && empty_cell == "redistribute") {
      res <- .wf_redistribute(res, min_cell, g)
    }

    plan_rows[[g]] <- data.frame(
      group = g,
      jdf[, dvars, drop = FALSE],
      pop = jdf$pop,
      n_sample = res$supp_final,
      ladder_level = res$level_used,
      resolved_cell = res$resolved,
      orphan = res$orphan,
      stringsAsFactors = FALSE
    )
    diag_rows[[g]] <- data.frame(
      group = g,
      n_cells_raw = nrow(jdf),
      n_cells_resolved = length(unique(res$resolved)),
      granularity_used = res$granularity_used,
      n_at_level0 = sum(res$level_used == 0),
      max_level_used = max(res$level_used),
      n_orphan = sum(res$orphan),
      pop_orphan = sum(jdf$pop[res$orphan]),
      stringsAsFactors = FALSE
    )
  }

  structure(
    list(
      plan = do.call(rbind, plan_rows),
      diagnostics = do.call(rbind, diag_rows),
      settings = list(
        min_cell = min_cell,
        granularity = granularity,
        empty_cell = empty_cell,
        ladder = ladder
      )
    ),
    class = "wf_poststrat_plan"
  )
}

#' Print a post-stratification plan
#'
#' @param x A `wf_poststrat_plan` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_poststrat_plan <- function(x, ...) {
  d <- x$diagnostics
  cat(sprintf(
    "<wf_poststrat_plan>  %d group(s); min_cell = %d\n",
    nrow(d),
    x$settings$min_cell
  ))
  cat(sprintf(
    "  granularity: %d adaptive, %d province\n",
    sum(d$granularity_used == "adaptive"),
    sum(d$granularity_used == "province")
  ))
  cat(sprintf(
    "  orphan cells: %d; orphan population: %s\n",
    sum(d$n_orphan),
    format(round(sum(d$pop_orphan)), big.mark = ",")
  ))
  print(utils::head(d, 12), row.names = FALSE)
  if (nrow(d) > 12) {
    cat(sprintf("  ... %d more groups (see $diagnostics)\n", nrow(d) - 12))
  }
  invisible(x)
}

#' Summarize a post-stratification plan
#'
#' @param object A `wf_poststrat_plan` object.
#' @param ... Unused.
#' @return The plan diagnostics data frame.
#' @export
summary.wf_poststrat_plan <- function(object, ...) {
  object$diagnostics
}
