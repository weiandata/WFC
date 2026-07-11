# ============================================================================
# WFC Extension 3 -- reference implementation, part 1 of 3 (releases 0.10-0.11)
# Usability foundations and the guided workflow.
#
# Prototype code: source AFTER library(WFC). It calls the installed public API
# (wf_precheck, wf_rake, wf_diagnose, wf_suggest_collapse, wf_apply_collapse,
# wf_target_population) and is NOT itself part of the installed API.
#
# Contents:
#   1. Output localization layer (.wf_lang / .wf_tr)          [design §4.2]
#   2. wf_auto_trim()  -- bias-variance frontier trim sweep    [design §3.3]
#   3. wf_suggest_ladder() -- collapse-ladder drafting         [design §3.3]
#   4. wf_report()     -- dual-audience, bilingual dossier     [design §3.1]
#   5. wf_autoweigh()  -- guided workflow with decision ledger [design §4.1]
#   6. plot() methods                                          [design §3.2]
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Output localization -----------------------------------------------------
# Messages catalogs; production version reads inst/i18n/*.dcf. Rendering only:
# condition classes and payloads are never localized (design P9).
# ----------------------------------------------------------------------------

.wf_i18n <- new.env(parent = emptyenv())
.wf_i18n$catalog <- list(
  en = c(
    rpt_title        = "Weighting quality report",
    rpt_group        = "Group",
    rpt_verdict_g    = "publishable separately",
    rpt_verdict_y    = "usable with caveats; prefer aggregated publication",
    rpt_verdict_r    = "do not publish separately; merge with a neighbour",
    rpt_ess          = "%s effective respondents out of %s (design effect %.1f)",
    rpt_trimmed      = "%d respondent weight(s) were capped to keep results stable",
    rpt_margin       = "largest remaining margin deviation: %.2f%%",
    aw_start         = "Starting guided weighting: %d rows, %d group(s), %d dimension(s).",
    aw_precheck_ok   = "Pre-check passed: sample and target are compatible.",
    aw_precheck_bad  = "Pre-check found %d blocking issue(s); trying declared remediations.",
    aw_collapse      = "Applied declared merge for dimension '%s' (issue: %s in group %s).",
    aw_no_fix        = "No pre-declared ladder can fix: %s. Declare a collapse ladder for this dimension in wf_dims() and re-run.",
    aw_trim          = "Recommended weight cap: %.1fx the average weight (keeps design effect below %.1f).",
    aw_done          = "Weighting finished: %d weights produced; overall verdict: %s.",
    aw_ask           = "Apply this remediation? (yes/no): "
  ),
  zh_CN = c(
    rpt_title        = "加权质量报告",
    rpt_group        = "群组",
    rpt_verdict_g    = "可单独发布",
    rpt_verdict_y    = "可用但需谨慎，建议合并发布",
    rpt_verdict_r    = "不建议单独发布，请与相邻群组合并",
    rpt_ess          = "有效样本量 %s / %s（设计效应 %.1f）",
    rpt_trimmed      = "为保持结果稳定，%d 个权重被封顶",
    rpt_margin       = "剩余最大边际偏差：%.2f%%",
    aw_start         = "开始引导式加权：%d 行，%d 个群组，%d 个维度。",
    aw_precheck_ok   = "预检查通过：样本与目标兼容。",
    aw_precheck_bad  = "预检查发现 %d 个阻塞性问题，尝试已声明的整改方案。",
    aw_collapse      = "已对维度 '%s' 应用声明的合并（问题：%s，群组 %s）。",
    aw_no_fix        = "没有预声明的阶梯能解决：%s。请在 wf_dims() 中为该维度声明折叠阶梯后重试。",
    aw_trim          = "建议权重上限：平均权重的 %.1f 倍（使设计效应低于 %.1f）。",
    aw_done          = "加权完成：产出 %d 个权重；总体结论：%s。",
    aw_ask           = "是否应用该整改？(yes/no)："
  )
)

.wf_lang <- function(lang = NULL) {
  if (!is.null(lang)) return(lang)
  opt <- getOption("wfc.lang", NULL)
  if (!is.null(opt)) return(opt)
  loc <- tolower(paste(Sys.getenv("LANGUAGE"), Sys.getenv("LANG"), Sys.getlocale("LC_CTYPE")))
  if (grepl("zh", loc, fixed = TRUE)) "zh_CN" else "en"
}

.wf_tr <- function(key, ..., lang = NULL) {
  lg <- .wf_lang(lang)
  cat <- .wf_i18n$catalog[[lg]]
  if (is.null(cat) || is.na(cat[key])) cat <- .wf_i18n$catalog$en
  sprintf(cat[[key]], ...)
}

# ----------------------------------------------------------------------------
# 2. wf_auto_trim() -----------------------------------------------------------
# Sweeps candidate weight caps; for each cap reports the worst-group design
# effect and worst residual margin error, then recommends the LOOSEST cap that
# meets both stated criteria. Recommends only -- the analyst sets the bound.
# ----------------------------------------------------------------------------

wf_auto_trim <- function(sample, target, id = NULL,
                         caps = c(2, 3, 4, 5, 6, 8, 10, 12),
                         lo = 0.05, max_deff = 6, max_residual = 0.02, ...) {
  one <- function(cap) {
    trim <- if (is.finite(cap)) c(lo, cap) else NULL
    w <- tryCatch(wf_rake(sample, target, id = id, trim = trim, ...),
                  error = function(e) NULL)
    if (is.null(w)) {
      return(data.frame(cap = cap, feasible = FALSE,
                        worst_deff = NA_real_, worst_residual = NA_real_))
    }
    d <- wf_diagnose(w, target = target)$table
    data.frame(
      cap = cap, feasible = TRUE,
      worst_deff = max(d$deff),
      worst_residual = if ("margin_maxerr" %in% names(d)) max(d$margin_maxerr) else NA_real_
    )
  }
  frontier <- do.call(rbind, lapply(c(sort(caps), Inf), one))
  ok <- frontier$feasible &
    frontier$worst_deff <= max_deff &
    (is.na(frontier$worst_residual) | frontier$worst_residual <= max_residual)
  finite_ok <- ok & is.finite(frontier$cap)
  recommended <- if (any(ok & !is.finite(frontier$cap))) {
    Inf                                   # no trimming needed at all
  } else if (any(finite_ok)) {
    max(frontier$cap[finite_ok])          # loosest cap meeting the criteria
  } else {
    NA_real_                              # nothing meets the criteria
  }
  structure(
    list(frontier = frontier, recommended_cap = recommended,
         criteria = list(max_deff = max_deff, max_residual = max_residual, lo = lo)),
    class = "wf_auto_trim"
  )
}

print.wf_auto_trim <- function(x, ...) {
  cat("<wf_auto_trim>  recommended cap:",
      if (is.na(x$recommended_cap)) "none meets the criteria"
      else if (!is.finite(x$recommended_cap)) "no trimming needed"
      else sprintf("%.1fx mean weight", x$recommended_cap), "\n")
  print(x$frontier, row.names = FALSE)
  invisible(x)
}

# ----------------------------------------------------------------------------
# 3. wf_suggest_ladder() ------------------------------------------------------
# Drafts a collapse ladder from observed sparsity: within each dimension,
# repeatedly merges the thinnest category (worst group counts) into its
# neighbour in declared level order until every merged category reaches
# min_cell. One ladder level per dimension, ordered by ascending affected
# sample share (least information loss first). Output is a DRAFT for review.
# ----------------------------------------------------------------------------

wf_suggest_ladder <- function(sample, target, dims, min_cell = 5) {
  dvars <- names(dims$vars)
  gkey <- if (is.null(target$by)) rep("_all_", nrow(sample))
          else trimws(as.character(sample[[target$by]]))
  drafts <- list()
  affected <- numeric(0)

  for (d in dvars) {
    v <- trimws(as.character(sample[[d]]))
    lev <- dims$vars[[d]]
    if (is.null(lev)) lev <- sort(unique(v[!is.na(v)]))
    worst <- vapply(lev, function(l) {
      per_group <- tapply(!is.na(v) & v == l, gkey, sum)
      min(as.numeric(per_group))
    }, numeric(1))
    if (all(worst >= min_cell)) next

    parts <- as.list(lev)                 # ordered partition of adjacent levels
    counts <- as.numeric(worst)
    while (length(counts) > 1 && any(counts < min_cell)) {
      i <- which.min(counts)
      j <- if (i == 1) 2
           else if (i == length(counts)) i - 1
           else if (counts[i - 1] <= counts[i + 1]) i - 1 else i + 1
      a <- min(i, j); b <- max(i, j)
      parts[[a]] <- c(parts[[a]], parts[[b]])
      counts[a] <- counts[a] + counts[b]
      parts[[b]] <- NULL
      counts <- counts[-b]
    }
    new_name <- vapply(parts, paste, "", collapse = "+")
    map <- stats::setNames(rep(new_name, lengths(parts)), unlist(parts))
    map <- map[map != names(map)]         # only genuine merges
    if (length(map) == 0) next
    drafts[[d]] <- map
    affected[d] <- mean(v %in% names(map), na.rm = TRUE)
  }

  ord <- names(sort(affected))            # least affected share first
  levels <- lapply(ord, function(d) stats::setNames(list(drafts[[d]]), d))
  names(levels) <- paste0("level", seq_along(ord))
  structure(
    list(levels = levels, affected_share = affected[ord], min_cell = min_cell),
    class = "wf_ladder_draft"
  )
}

#' Materialize a reviewed draft into a validated wf_collapse_ladder.
as_ladder <- function(draft, dims) {
  stopifnot(inherits(draft, "wf_ladder_draft"))
  do.call(wf_collapse_ladder, c(list(dims), draft$levels))
}

print.wf_ladder_draft <- function(x, ...) {
  cat(sprintf("<wf_ladder_draft>  %d level(s); min_cell = %d  (review before use)\n",
              length(x$levels), x$min_cell))
  for (nm in names(x$levels)) {
    d <- names(x$levels[[nm]])
    map <- x$levels[[nm]][[1]]
    cat(sprintf("  %s [%s, %.0f%% of rows affected]: %s\n", nm, d,
                100 * x$affected_share[[d]],
                paste(sprintf("%s->%s", names(map), map), collapse = ", ")))
  }
  invisible(x)
}

# ----------------------------------------------------------------------------
# 4. wf_report() --------------------------------------------------------------
# One structured object, two renderings. audience = "manager" projects the
# analyst dossier onto a traffic-light summary in plain language (P7).
# ----------------------------------------------------------------------------

wf_report <- function(w, target = NULL,
                      audience = c("manager", "analyst"),
                      lang = NULL,
                      output = c("object", "markdown", "html"),
                      file = NULL) {
  audience <- match.arg(audience)
  output <- match.arg(output)
  diag <- wf_diagnose(w, target = target)$table

  light <- ifelse(diag$verdict == "OK", "green",
           ifelse(diag$verdict == "usable with caveats", "yellow", "red"))
  body <- data.frame(diag, light = light, stringsAsFactors = FALSE)

  lines <- c(paste0("# ", .wf_tr("rpt_title", lang = lang)), "")
  for (i in seq_len(nrow(body))) {
    key <- c(green = "rpt_verdict_g", yellow = "rpt_verdict_y", red = "rpt_verdict_r")[body$light[i]]
    lines <- c(lines, sprintf("## %s %s -- %s",
                              .wf_tr("rpt_group", lang = lang),
                              body$group[i], .wf_tr(key, lang = lang)))
    lines <- c(lines, paste0("- ", .wf_tr("rpt_ess",
                             format(body$ess[i], big.mark = ","),
                             format(body$n[i], big.mark = ","),
                             body$deff[i], lang = lang)))
    if (audience == "analyst") {
      lines <- c(lines, sprintf("- min/mean/max weight: %.3g / %.3g / %.3g; max/mean: %.1f",
                                body$min_w[i], body$mean_w[i], body$max_w[i],
                                body$max_over_mean[i]))
    }
    if (!is.na(body$trimmed[i]) && body$trimmed[i] > 0) {
      lines <- c(lines, paste0("- ", .wf_tr("rpt_trimmed", body$trimmed[i], lang = lang)))
    }
    if ("margin_maxerr" %in% names(body) && !is.na(body$margin_maxerr[i])) {
      lines <- c(lines, paste0("- ", .wf_tr("rpt_margin", 100 * body$margin_maxerr[i], lang = lang)))
    }
    lines <- c(lines, "")
  }

  res <- structure(
    list(table = body, markdown = lines, audience = audience,
         lang = .wf_lang(lang), provenance = w$provenance),
    class = "wf_quality_report"
  )
  if (output == "object") return(res)
  text <- if (output == "markdown") paste(lines, collapse = "\n")
          else paste0("<!DOCTYPE html><html><head><meta charset='utf-8'></head><body><pre>\n",
                      paste(lines, collapse = "\n"), "\n</pre></body></html>")
  if (!is.null(file)) { writeLines(text, file, useBytes = TRUE); return(invisible(res)) }
  cat(text, "\n")
  invisible(res)
}

print.wf_quality_report <- function(x, ...) {
  cat(paste(x$markdown, collapse = "\n"), "\n")
  invisible(x)
}

# ----------------------------------------------------------------------------
# 5. wf_autoweigh() -----------------------------------------------------------
# The guided path. One engine, two paths (P8): this function only orchestrates
# the public API and records every automated choice in a decision ledger.
# It can never bypass a blocking precheck (P1): remediation is limited to
# ladders/maps the user declared in wf_dims(); anything else stops with a
# plain-language explanation of what to declare.
# ----------------------------------------------------------------------------

wf_autoweigh <- function(sample, population, dims,
                         key_map = NULL, count = NULL, by = NULL, id = NULL,
                         method = c("auto", "raking", "logit"),
                         bounds = NULL,
                         trim = "auto", max_deff = 6,
                         interactive = base::interactive(),
                         lang = NULL, ...) {
  method <- match.arg(method)
  ledger <- list()
  note <- function(action, detail, artifact = NULL) {
    ledger[[length(ledger) + 1]] <<- list(
      step = length(ledger) + 1L, action = action,
      detail = detail, artifact = artifact, time = Sys.time()
    )
    message(detail)
  }

  # -- target ----------------------------------------------------------------
  target <- if (inherits(population, "wf_target")) {
    population
  } else {
    if (is.null(key_map) || is.null(count)) {
      stop("Provide `key_map` and `count` when `population` is a raw data frame.")
    }
    wf_target_population(population, key_map, count, dims, by = by)
  }
  note("start", .wf_tr("aw_start", nrow(sample), length(target$groups),
                       length(target$dims), lang = lang))

  # -- precheck / remediation loop --------------------------------------------
  cur_sample <- sample
  cur_target <- target
  for (round in 1:2) {
    pc <- wf_precheck(cur_sample, cur_target, id = id)
    if (pc$ok) {
      note("precheck", .wf_tr("aw_precheck_ok", lang = lang), artifact = pc)
      break
    }
    n_err <- sum(pc$issues$severity == "error")
    note("precheck", .wf_tr("aw_precheck_bad", n_err, lang = lang), artifact = pc)
    if (round == 2) {
      bad <- pc$issues[pc$issues$severity == "error", , drop = FALSE]
      stop(.wf_tr("aw_no_fix",
                  paste(unique(stats::na.omit(bad$dim)), collapse = ", "),
                  lang = lang))
    }
    plan <- wf_suggest_collapse(pc, dims)
    if (length(plan$maps) == 0) {
      bad <- pc$issues[pc$issues$severity == "error", , drop = FALSE]
      stop(.wf_tr("aw_no_fix",
                  paste(unique(stats::na.omit(bad$dim)), collapse = ", "),
                  lang = lang))
    }
    if (interactive) {
      print(plan)
      ans <- tolower(trimws(readline(.wf_tr("aw_ask", lang = lang))))
      if (!ans %in% c("y", "yes")) stop("Remediation declined; weighting stopped.")
    }
    out <- wf_apply_collapse(cur_sample, cur_target, plan)
    cur_sample <- out$sample
    cur_target <- out$target
    for (i in seq_len(nrow(plan$actions))) {
      note("collapse",
           .wf_tr("aw_collapse", plan$actions$dim[i], plan$actions$check[i],
                  plan$actions$group[i], lang = lang),
           artifact = plan)
    }
  }

  # -- trimming recommendation -------------------------------------------------
  trim_arg <- NULL
  if (identical(trim, "auto") && method %in% c("auto", "raking")) {
    at <- wf_auto_trim(cur_sample, cur_target, id = id, max_deff = max_deff, ...)
    if (is.finite(at$recommended_cap)) {
      trim_arg <- c(at$criteria$lo, at$recommended_cap)
      note("trim", .wf_tr("aw_trim", at$recommended_cap, max_deff, lang = lang),
           artifact = at)
    }
  } else if (is.numeric(trim) && length(trim) == 2) {
    trim_arg <- trim
  }

  # -- calibrate ---------------------------------------------------------------
  w <- if (method == "logit") {
    wf_calibrate(cur_sample, cur_target, method = "logit",
                 bounds = if (is.null(bounds)) c(0.3, 3) else bounds, id = id, ...)
  } else {
    wf_rake(cur_sample, cur_target, id = id, trim = trim_arg, ...)
  }

  diag <- wf_diagnose(w, target = cur_target)
  report <- wf_report(w, target = cur_target, audience = "manager", lang = lang)
  overall <- if (all(diag$table$verdict == "OK")) .wf_tr("rpt_verdict_g", lang = lang)
             else if (any(diag$table$verdict %in% c("FAILED", "do not publish separately")))
               .wf_tr("rpt_verdict_r", lang = lang)
             else .wf_tr("rpt_verdict_y", lang = lang)
  note("done", .wf_tr("aw_done", nrow(w$data), overall, lang = lang))

  structure(
    list(weights = w, diagnostics = diag, report = report,
         ledger = ledger, sample = cur_sample, target = cur_target),
    class = "wf_autoweigh_result"
  )
}

print.wf_autoweigh_result <- function(x, ...) {
  cat(sprintf("<wf_autoweigh_result>  %d weight(s); %d ledger step(s)\n",
              nrow(x$weights$data), length(x$ledger)))
  for (e in x$ledger) cat(sprintf("  [%d] %-9s %s\n", e$step, e$action, e$detail))
  invisible(x)
}

# ----------------------------------------------------------------------------
# 6. plot() methods (base graphics, zero dependencies) ------------------------
# ----------------------------------------------------------------------------

plot.wf_weights <- function(x, max_groups = 9, ...) {
  groups <- unique(x$data$group)[seq_len(min(9, length(unique(x$data$group))))]
  old <- graphics::par(mfrow = grDevices::n2mfrow(length(groups)))
  on.exit(graphics::par(old))
  for (g in groups) {
    wt <- x$data$weight[x$data$group == g]
    graphics::hist(wt, main = paste("Group", g), xlab = "weight",
                   col = "grey85", border = "white", ...)
    graphics::abline(v = mean(wt), lty = 2)
  }
  invisible(x)
}

plot.wf_diagnostics <- function(x, ...) {
  t <- x$table[order(x$table$deff), ]
  graphics::dotchart(t$deff, labels = t$group, xlab = "design effect", ...)
  graphics::abline(v = c(3, 10), lty = 3)
  invisible(x)
}

plot.wf_auto_trim <- function(x, ...) {
  f <- x$frontier[x$frontier$feasible & is.finite(x$frontier$cap), ]
  graphics::plot(f$cap, f$worst_deff, type = "b", xlab = "trim cap (x mean)",
                 ylab = "worst design effect", ...)
  graphics::abline(h = x$criteria$max_deff, lty = 3)
  if (is.finite(x$recommended_cap)) graphics::abline(v = x$recommended_cap, lty = 2)
  invisible(x)
}
