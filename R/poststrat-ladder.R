#' Declare a post-stratification collapse ladder
#'
#' Creates an ordered, cumulative, validated category-collapse ladder for
#' post-stratification cell resolution. Level 0 is the raw classification; each
#' named level applies one additional set of dimension maps.
#'
#' @param dims A `wf_dims` object.
#' @param ... Named ladder levels, each a list of named character vectors in
#'   the form `old = "new"` by dimension.
#'
#' @return A `wf_collapse_ladder` object.
#' @export
#'
#' @examples
#' dims <- wf_dims(age = c("young", "old"), education = c("low", "high"))
#' wf_collapse_ladder(
#'   dims,
#'   level1 = list(age = c(young = "all", old = "all"))
#' )
wf_collapse_ladder <- function(dims, ...) {
  if (!inherits(dims, "wf_dims")) {
    wf_abort("`dims` must be a wf_dims object.", "wf_error_input")
  }
  steps <- list(...)
  if (length(steps) > 0 && (is.null(names(steps)) || any(names(steps) == ""))) {
    wf_abort(
      "Ladder levels must be named (for example, level1 = list(...)).",
      "wf_error_input"
    )
  }

  dvars <- names(dims$vars)
  universe <- lapply(dvars, function(d) dims$vars[[d]])
  names(universe) <- dvars

  for (lv in seq_along(steps)) {
    step <- steps[[lv]]
    bad_d <- setdiff(names(step), dvars)
    if (length(bad_d) > 0) {
      wf_abort(
        sprintf(
          "Ladder level '%s' references unknown dimension(s): %s",
          names(steps)[lv],
          paste(bad_d, collapse = ", ")
        ),
        "wf_error_input",
        list(level = names(steps)[lv], dims = bad_d)
      )
    }

    for (d in names(step)) {
      raw_map <- step[[d]]
      if (is.null(names(raw_map))) {
        wf_abort(
          sprintf(
            "Ladder level '%s', dim '%s': map must be a named vector.",
            names(steps)[lv],
            d
          ),
          "wf_error_input"
        )
      }
      map <- .chr(raw_map)
      names(map) <- .chr(names(raw_map))

      if (!is.null(universe[[d]])) {
        unknown <- setdiff(names(map), universe[[d]])
        if (length(unknown) > 0) {
          wf_abort(
            sprintf(
              "Ladder level '%s', dim '%s': source categories not present at this level: %s",
              names(steps)[lv],
              d,
              paste(unknown, collapse = ", ")
            ),
            "wf_error_input",
            list(level = names(steps)[lv], dim = d, unknown = unknown)
          )
        }
        kept <- setdiff(universe[[d]], names(map))
        universe[[d]] <- unique(c(kept, unname(map)))
      } else {
        universe[[d]] <- unique(unname(map))
      }
      step[[d]] <- map
    }
    steps[[lv]] <- step
  }

  structure(
    list(dims = dvars, steps = steps, n_levels = length(steps)),
    class = "wf_collapse_ladder"
  )
}
