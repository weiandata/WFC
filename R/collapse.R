#' Apply one category collapse map.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param plan List with `dim` and named character vector `map`.
#' @keywords internal
#' @noRd
.wf_apply_one_collapse <- function(sample, target, plan) {
  d <- plan$dim
  map <- plan$map
  if (!d %in% target$dims) {
    wf_abort(sprintf("Collapse plan targets unknown dimension '%s'.", d), "wf_error_input")
  }
  v <- .chr(sample[[d]])
  hit <- !is.na(v) & v %in% names(map)
  v[hit] <- map[v[hit]]
  sample[[d]] <- v
  for (g in names(target$groups)) {
    m <- target$groups[[g]]$margins[[d]]
    key <- names(m)
    hit <- key %in% names(map)
    key[hit] <- map[key[hit]]
    target$groups[[g]]$margins[[d]] <- .wf_margin_vector(tapply(as.numeric(m), key, sum))
  }
  if (!is.null(target$joint)) {
    for (g in names(target$joint)) {
      joint <- target$joint[[g]]
      key <- .chr(joint[[d]])
      hit <- key %in% names(map)
      key[hit] <- map[key[hit]]
      joint[[d]] <- key
      target$joint[[g]] <- stats::aggregate(
        joint["pop"],
        joint[target$dims],
        sum
      )
    }
  }
  .wf_validate_target(target)
  list(sample = sample, target = target)
}

#' Apply a category collapse plan
#'
#' Applies category-merge maps consistently to sample data and a target object.
#'
#' @param sample Sample data frame.
#' @param target A `wf_target` object.
#' @param plan List with `dim` and named character vector `map`, or a
#'   `wf_collapse_plan` object from `wf_suggest_collapse()`.
#'
#' @return A list with collapsed `sample` and `target`.
#' @export
wf_apply_collapse <- function(sample, target, plan) {
  if (inherits(plan, "wf_collapse_plan")) {
    out <- list(sample = sample, target = target)
    for (m in plan$maps) {
      out <- .wf_apply_one_collapse(out$sample, out$target, m)
    }
    out$target$meta$collapsed <- c(out$target$meta$collapsed, list(plan))
    return(out)
  }

  out <- .wf_apply_one_collapse(sample, target, plan)
  out$target$meta$collapsed <- c(out$target$meta$collapsed, list(plan))
  out
}

#' Suggest collapse plans from precheck findings
#'
#' Converts selected precheck issues into a reviewable collapse plan using
#' collapse ladders declared in `wf_dims()`.
#'
#' @param precheck A `wf_precheck` object.
#' @param dims A `wf_dims` object with optional collapse ladders.
#' @param checks Precheck identifiers eligible for collapse suggestions.
#' @param max_steps Maximum number of ladder steps to inspect per dimension.
#'
#' @return A `wf_collapse_plan` object.
#' @export
wf_suggest_collapse <- function(precheck, dims,
                                checks = c("cat_infeasible", "support_thin", "risk_extreme_ratio"),
                                max_steps = 1) {
  if (!inherits(precheck, "wf_precheck")) {
    wf_abort("`precheck` must be a wf_precheck object.", "wf_error_input")
  }
  if (!inherits(dims, "wf_dims")) {
    wf_abort("`dims` must be a wf_dims object.", "wf_error_input")
  }
  if (length(max_steps) != 1 || !is.finite(max_steps) || max_steps < 1) {
    wf_abort("`max_steps` must be a positive integer.", "wf_error_input")
  }

  issues <- precheck$issues
  issues <- issues[
    issues$check %in% checks & !is.na(issues$dim) & !is.na(issues$category),
    ,
    drop = FALSE
  ]
  actions <- data.frame(
    group = character(),
    dim = character(),
    category = character(),
    check = character(),
    step = character(),
    stringsAsFactors = FALSE
  )
  maps <- list()
  unresolved <- issues[0, , drop = FALSE]

  for (i in seq_len(nrow(issues))) {
    d <- issues$dim[i]
    cat <- strsplit(issues$category[i], ",", fixed = TRUE)[[1]][1]
    cat <- trimws(cat)
    ladder <- dims$collapse[[d]]
    found <- FALSE

    if (!is.null(ladder)) {
      step_names <- names(ladder)
      if (is.null(step_names)) {
        step_names <- as.character(seq_along(ladder))
      }
      for (s in utils::head(seq_along(ladder), max_steps)) {
        map <- .chr(ladder[[s]])
        names(map) <- .chr(names(ladder[[s]]))
        if (cat %in% names(map)) {
          actions <- rbind(
            actions,
            data.frame(
              group = issues$group[i],
              dim = d,
              category = cat,
              check = issues$check[i],
              step = step_names[[s]],
              stringsAsFactors = FALSE
            )
          )
          existing <- which(vapply(
            maps,
            function(x) identical(x$dim, d) && identical(x$map, map),
            logical(1)
          ))
          if (length(existing) == 0) {
            maps[[length(maps) + 1]] <- list(dim = d, map = map)
          }
          found <- TRUE
          break
        }
      }
    }

    if (!found) {
      unresolved <- rbind(unresolved, issues[i, , drop = FALSE])
    }
  }

  structure(
    list(
      actions = actions,
      maps = maps,
      source_checks = issues,
      unresolved = unresolved,
      created = Sys.time()
    ),
    class = "wf_collapse_plan"
  )
}

#' Print a collapse plan
#'
#' @param x A `wf_collapse_plan` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_collapse_plan <- function(x, ...) {
  cat(sprintf(
    "<wf_collapse_plan>  %d action(s), %d map(s), %d unresolved issue(s)\n",
    nrow(x$actions),
    length(x$maps),
    nrow(x$unresolved)
  ))
  if (nrow(x$actions) > 0) {
    print(utils::head(x$actions, 10), row.names = FALSE)
  }
  invisible(x)
}
