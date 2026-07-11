#' Convert values to report-safe text.
#'
#' @param x Atomic vector.
#' @keywords internal
#' @noRd
.wf_report_text <- function(x) {
  if (is.numeric(x)) {
    out <- format(x, digits = 6, trim = TRUE, scientific = FALSE)
  } else {
    out <- as.character(x)
  }
  out[is.na(x)] <- ""
  out
}

#' Escape text for Markdown tables.
#'
#' @param x Character vector.
#' @keywords internal
#' @noRd
.wf_report_markdown_escape <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("|", "\\|", x, fixed = TRUE)
  gsub("\n", " ", x, fixed = TRUE)
}

#' Escape text for HTML.
#'
#' @param x Character vector.
#' @keywords internal
#' @noRd
.wf_report_html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  gsub("'", "&#39;", x, fixed = TRUE)
}

#' Render a data frame as a Markdown table.
#'
#' @param x Data frame.
#' @param lang Output language.
#' @keywords internal
#' @noRd
.wf_report_markdown_table <- function(x, lang = NULL) {
  if (!is.data.frame(x) || ncol(x) == 0) {
    return("_No rows available._")
  }
  labels <- vapply(names(x), .wf_i18n_label, character(1), lang = lang)
  header <- paste0("| ", paste(labels, collapse = " | "), " |")
  rule <- paste0("| ", paste(rep("---", ncol(x)), collapse = " | "), " |")
  if (nrow(x) == 0) {
    return(paste(c(header, rule), collapse = "\n"))
  }
  rows <- vapply(seq_len(nrow(x)), function(i) {
    values <- vapply(x[i, , drop = FALSE], function(value) {
      .wf_report_markdown_escape(.wf_report_text(value))
    }, character(1))
    paste0("| ", paste(values, collapse = " | "), " |")
  }, character(1))
  paste(c(header, rule, rows), collapse = "\n")
}

#' Render a data frame as an HTML table.
#'
#' @param x Data frame.
#' @param lang Output language.
#' @keywords internal
#' @noRd
.wf_report_html_table <- function(x, lang = NULL) {
  if (!is.data.frame(x) || ncol(x) == 0) {
    return("<p><em>No rows available.</em></p>")
  }
  labels <- vapply(names(x), .wf_i18n_label, character(1), lang = lang)
  head <- paste0(
    "<thead><tr>",
    paste0("<th>", .wf_report_html_escape(labels), "</th>", collapse = ""),
    "</tr></thead>"
  )
  body <- if (nrow(x) == 0) {
    "<tbody></tbody>"
  } else {
    rows <- vapply(seq_len(nrow(x)), function(i) {
      values <- vapply(x[i, , drop = FALSE], function(value) {
        .wf_report_html_escape(.wf_report_text(value))
      }, character(1))
      paste0(
        "<tr>",
        paste0("<td>", values, "</td>", collapse = ""),
        "</tr>"
      )
    }, character(1))
    paste0("<tbody>", paste(rows, collapse = ""), "</tbody>")
  }
  paste0("<table>", head, body, "</table>")
}

#' Add manager decision columns to weight diagnostics.
#'
#' @param diagnostics Diagnostic table.
#' @param lang Output language.
#' @keywords internal
#' @noRd
.wf_report_manager_weights <- function(diagnostics, lang = NULL) {
  light <- ifelse(
    diagnostics$verdict == "OK",
    "green",
    ifelse(diagnostics$verdict == "usable with caveats", "yellow", "red")
  )
  verdict_label <- vapply(light, function(value) {
    .wf_tr(paste0("verdict_", value), lang = lang)
  }, character(1))
  action <- vapply(light, function(value) {
    .wf_tr(paste0("action_weights_", value), lang = lang)
  }, character(1))
  cbind(
    diagnostics,
    verdict_label = unname(verdict_label),
    light = unname(light),
    publish_separately = light == "green",
    action = unname(action)
  )
}

#' Extract structured method-specific sections from weights.
#'
#' @param w A `wf_weights` object.
#' @keywords internal
#' @noRd
.wf_report_weight_sections <- function(w) {
  sections <- list()
  if (!is.null(w$overlap)) {
    sections$propensity_overlap <- data.frame(
      threshold = w$overlap$threshold,
      n_boundary = w$overlap$n_boundary,
      n_online = w$overlap$n_online,
      stringsAsFactors = FALSE
    )
    online <- w$overlap$online
    reference <- w$overlap$reference
    sections$propensity_quantiles <- rbind(
      data.frame(
        source = "online",
        quantile = names(online),
        propensity = unname(online),
        stringsAsFactors = FALSE
      ),
      data.frame(
        source = "reference",
        quantile = names(reference),
        propensity = unname(reference),
        stringsAsFactors = FALSE
      )
    )
  }
  if (inherits(w, "wf_attrition_weights") && is.data.frame(w$balance)) {
    sections$attrition_balance <- w$balance
  } else if (is.data.frame(w$balance)) {
    sections$propensity_balance <- w$balance
  }
  if (inherits(w, "wf_attrition_weights") &&
      is.data.frame(w$retention_probability)) {
    sections$attrition_retention <- w$retention_probability
  }
  if (is.data.frame(w$cell_report)) {
    sections$poststrat_cells <- w$cell_report
  }
  if (is.data.frame(w$collapse_map)) {
    sections$poststrat_collapse_map <- w$collapse_map
  }
  if (is.data.frame(w$relaxation)) {
    sections$soft_relaxation <- w$relaxation
  }
  if (is.data.frame(w$moments)) {
    sections$entropy_moments <- w$moments
  }
  if (!is.null(w$provenance$stages)) {
    stage_rows <- lapply(seq_along(w$provenance$stages), function(i) {
      stage <- w$provenance$stages[[i]]
      data.frame(
        stage = if (is.null(stage$stage)) i else stage$stage,
        label = if (is.null(stage$label)) paste0("stage", i) else stage$label,
        method = if (is.null(stage$provenance$method)) NA_character_ else
          stage$provenance$method,
        stringsAsFactors = FALSE
      )
    })
    sections$pipeline_stages <- do.call(rbind, stage_rows)
  }
  sections
}

#' Build the report payload for a blend result.
#'
#' @param w A `wf_blend_result`.
#' @param audience Report audience.
#' @param lang Output language.
#' @keywords internal
#' @noRd
.wf_report_blend <- function(w, audience, lang = NULL) {
  if (!is.data.frame(w$summary) || nrow(w$summary) == 0) {
    wf_abort(
      "A blend report requires a non-empty `$summary`; blend with an outcome first.",
      "wf_error_input"
    )
  }
  table <- w$summary
  if (audience == "manager") {
    reason <- if (is.data.frame(w$lambda)) w$lambda else data.frame()
    one_source_groups <- if (nrow(reason) > 0) {
      unique(reason$group[reason$lambda_reason %in% c("online_only", "offline_only")])
    } else {
      character()
    }
    trimmed_groups <- if (nrow(reason) > 0 && "lambda_trimmed" %in% names(reason)) {
      unique(reason$group[reason$lambda_trimmed])
    } else {
      character()
    }
    light <- vapply(table$group, function(group) {
      global <- identical(group, "__overall__")
      if ((global && length(one_source_groups) > 0) || group %in% one_source_groups) {
        "red"
      } else if ((global && length(trimmed_groups) > 0) || group %in% trimmed_groups) {
        "yellow"
      } else {
        "green"
      }
    }, character(1))
    verdict_label <- vapply(light, function(value) {
      .wf_tr(paste0("verdict_", value), lang = lang)
    }, character(1))
    action <- vapply(light, function(value) {
      .wf_tr(paste0("action_blend_", value), lang = lang)
    }, character(1))
    table <- cbind(
      table,
      verdict_label = unname(verdict_label),
      light = unname(light),
      publish_separately = light == "green",
      action = unname(action)
    )
  }
  sections <- list()
  if (is.data.frame(w$lambda)) sections$blend_lambda <- w$lambda
  if (is.data.frame(w$sensitivity)) sections$blend_sensitivity <- w$sensitivity
  if (is.data.frame(w$diagnostics$source_support)) {
    sections$blend_source_support <- w$diagnostics$source_support
  }
  list(table = table, sections = sections)
}

#' Render a quality report as Markdown.
#'
#' @param report A `wf_quality_report`.
#' @keywords internal
#' @noRd
.wf_report_markdown <- function(report) {
  chunks <- c(
    paste0("# ", report$title),
    "",
    paste0(
      .wf_tr("report_audience", lang = report$language),
      ": ",
      .wf_tr(paste0("audience_", report$audience), lang = report$language)
    ),
    "",
    .wf_report_markdown_table(report$table, lang = report$language)
  )
  if (length(report$sections) > 0) {
    for (section in names(report$sections)) {
      label <- .wf_i18n_section(section, report$language)
      chunks <- c(
        chunks,
        "",
        paste0("## ", label),
        "",
        .wf_report_markdown_table(
          report$sections[[section]],
          lang = report$language
        )
      )
    }
  }
  paste(chunks, collapse = "\n")
}

#' Render a quality report as standalone base HTML.
#'
#' @param report A `wf_quality_report`.
#' @keywords internal
#' @noRd
.wf_report_html <- function(report) {
  sections <- character()
  if (length(report$sections) > 0) {
    sections <- vapply(names(report$sections), function(section) {
      label <- .wf_i18n_section(section, report$language)
      paste0(
        "<section><h2>", .wf_report_html_escape(label), "</h2>",
        .wf_report_html_table(
          report$sections[[section]],
          lang = report$language
        ),
        "</section>"
      )
    }, character(1))
  }
  paste0(
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\">",
    "<title>", .wf_report_html_escape(report$title), "</title>",
    "<style>body{font-family:sans-serif;max-width:1100px;margin:2rem auto;}",
    "table{border-collapse:collapse;width:100%;margin-bottom:1.5rem;}",
    "th,td{border:1px solid #ccc;padding:.35rem;text-align:left;}</style>",
    "</head><body><h1>", .wf_report_html_escape(report$title), "</h1>",
    "<p>", .wf_report_html_escape(.wf_tr(
      "report_audience",
      lang = report$language
    )), ": ", .wf_report_html_escape(.wf_tr(
      paste0("audience_", report$audience),
      lang = report$language
    )), "</p>",
    .wf_report_html_table(report$table, lang = report$language),
    paste(sections, collapse = ""),
    "</body></html>"
  )
}

#' Build a weighting quality report
#'
#' Creates one structured dossier with manager and analyst projections. It can
#' report calibrated/composed weights or a blend result and render the same
#' payload as Markdown or dependency-free HTML.
#'
#' @param w A `wf_weights` or `wf_blend_result` object.
#' @param target Optional `wf_target` for margin-residual diagnostics.
#' @param audience Report projection: `"manager"` or `"analyst"`.
#' @param lang Output language. Resolution follows explicit argument,
#'   `options(wfc.lang)`, session locale, then English fallback.
#' @param output Return a structured object, Markdown, or standalone HTML.
#' @param file Optional output path for Markdown or HTML.
#'
#' @return A `wf_quality_report` for `output = "object"`; otherwise a rendered
#'   character string, or invisibly the structured report when `file` is used.
#' @export
#' @examples
#' data(wfc_example)
#' target <- wf_target_population(
#'   wfc_example$population,
#'   c(gender = "gender", age = "age"),
#'   "count",
#'   wfc_example$dims,
#'   by = "province"
#' )
#' weights <- wf_rake(wfc_example$sample, target, id = "id")
#' wf_report(weights, target, audience = "manager")
wf_report <- function(w, target = NULL,
                      audience = c("manager", "analyst"),
                      lang = NULL,
                      output = c("object", "markdown", "html"),
                      file = NULL) {
  audience <- match.arg(audience)
  output <- match.arg(output)
  language <- .wf_lang(lang)
  if (!is.null(file) &&
      (length(file) != 1 || is.na(file) || !nzchar(file))) {
    wf_abort("`file` must be NULL or one non-empty path.", "wf_error_input")
  }
  if (output == "object" && !is.null(file)) {
    wf_abort("`file` requires output = 'markdown' or 'html'.", "wf_error_input")
  }
  if (!is.null(target) && !inherits(target, "wf_target")) {
    wf_abort("`target` must be NULL or a wf_target object.", "wf_error_input")
  }

  if (inherits(w, "wf_weights")) {
    diagnostics <- wf_diagnose(w, target = target)$table
    table <- if (audience == "manager") {
      .wf_report_manager_weights(diagnostics, language)
    } else {
      light <- ifelse(
        diagnostics$verdict == "OK",
        "green",
        ifelse(diagnostics$verdict == "usable with caveats", "yellow", "red")
      )
      cbind(
        diagnostics,
        verdict_label = vapply(light, function(value) {
          .wf_tr(paste0("verdict_", value), lang = language)
        }, character(1))
      )
    }
    sections <- .wf_report_weight_sections(w)
    source_type <- "weights"
  } else if (inherits(w, "wf_blend_result")) {
    payload <- .wf_report_blend(w, audience, language)
    table <- payload$table
    sections <- payload$sections
    source_type <- "blend"
  } else {
    wf_abort(
      "`w` must be a wf_weights or wf_blend_result object.",
      "wf_error_input"
    )
  }

  report <- structure(
    list(
      title = .wf_tr("report_title", lang = language),
      table = table,
      sections = sections,
      audience = audience,
      language = language,
      source_type = source_type,
      provenance = w$provenance
    ),
    class = "wf_quality_report"
  )
  if (output == "object") {
    return(report)
  }
  rendered <- if (output == "markdown") {
    .wf_report_markdown(report)
  } else {
    .wf_report_html(report)
  }
  if (!is.null(file)) {
    writeLines(rendered, con = file, useBytes = TRUE)
    return(invisible(report))
  }
  rendered
}

#' Print a weighting quality report
#'
#' @param x A `wf_quality_report` object.
#' @param ... Unused.
#' @return Invisibly returns `x`.
#' @export
print.wf_quality_report <- function(x, ...) {
  cat(.wf_report_markdown(x), "\n")
  invisible(x)
}

#' Convert a weighting quality report to a data frame
#'
#' @param x A `wf_quality_report` object.
#' @param ... Unused.
#' @return The report's primary table.
#' @export
as.data.frame.wf_quality_report <- function(x, ...) {
  x$table
}
