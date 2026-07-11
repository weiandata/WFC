#' Cached localized output catalogs.
#'
#' @keywords internal
#' @noRd
.wf_i18n_cache <- new.env(parent = emptyenv())

#' Normalize an explicit or configured language value.
#'
#' @param value Language value.
#' @param strict Whether unsupported values should raise an input error.
#' @keywords internal
#' @noRd
.wf_normalize_lang <- function(value, strict = TRUE) {
  if (length(value) != 1 || is.na(value) || !is.character(value) ||
      !nzchar(trimws(value))) {
    if (strict) {
      wf_abort("`lang` must be one supported language name.", "wf_error_input")
    }
    return("en")
  }
  normalized <- tolower(gsub("-", "_", trimws(value), fixed = TRUE))
  if (grepl("^en($|_)", normalized)) {
    return("en")
  }
  if (grepl("^zh($|_)", normalized)) {
    return("zh_CN")
  }
  if (strict) {
    wf_abort(
      sprintf("Unsupported output language '%s'. Supported languages: en, zh_CN.", value),
      "wf_error_input",
      list(lang = value)
    )
  }
  "en"
}

#' Resolve the current output language.
#'
#' @param lang Optional explicit language.
#' @keywords internal
#' @noRd
.wf_lang <- function(lang = NULL) {
  if (!is.null(lang)) {
    return(.wf_normalize_lang(lang, strict = TRUE))
  }
  option <- getOption("wfc.lang", NULL)
  if (!is.null(option)) {
    return(.wf_normalize_lang(option, strict = TRUE))
  }
  locale <- tolower(paste(
    Sys.getenv("LANGUAGE"),
    Sys.getenv("LC_ALL"),
    Sys.getenv("LC_MESSAGES"),
    Sys.getenv("LANG"),
    Sys.getlocale("LC_CTYPE")
  ))
  if (grepl("zh", locale, fixed = TRUE)) "zh_CN" else "en"
}

#' Locate one installed or development output catalog.
#'
#' @param lang Normalized language.
#' @keywords internal
#' @noRd
.wf_i18n_path <- function(lang) {
  filename <- paste0(lang, ".dcf")
  path <- system.file("i18n", filename, package = "WFC")
  if (!nzchar(path)) {
    development <- file.path("inst", "i18n", filename)
    if (file.exists(development)) path <- development
  }
  path
}

#' Load a localized output catalog.
#'
#' @param lang Normalized language.
#' @keywords internal
#' @noRd
.wf_i18n_catalog <- function(lang) {
  lang <- .wf_normalize_lang(lang, strict = TRUE)
  if (exists(lang, envir = .wf_i18n_cache, inherits = FALSE)) {
    return(get(lang, envir = .wf_i18n_cache, inherits = FALSE))
  }
  path <- .wf_i18n_path(lang)
  if (!nzchar(path) || !file.exists(path)) {
    wf_abort(
      sprintf("Output catalog '%s' is missing from the installed package.", lang),
      "wf_error_internal",
      list(lang = lang)
    )
  }
  raw <- tryCatch(read.dcf(path), error = function(e) e)
  if (inherits(raw, "error") || nrow(raw) != 1) {
    wf_abort(
      sprintf("Output catalog '%s' is malformed.", lang),
      "wf_error_internal",
      list(lang = lang)
    )
  }
  catalog <- as.character(raw[1, ])
  names(catalog) <- colnames(raw)
  assign(lang, catalog, envir = .wf_i18n_cache)
  catalog
}

#' Translate one human-facing output string.
#'
#' @param key Stable catalog key.
#' @param ... Values interpolated with `sprintf()`.
#' @param lang Optional language selector.
#' @keywords internal
#' @noRd
.wf_tr <- function(key, ..., lang = NULL) {
  language <- .wf_lang(lang)
  catalog <- .wf_i18n_catalog(language)
  english <- .wf_i18n_catalog("en")
  template <- unname(catalog[key])
  if (length(template) == 0 || is.na(template)) {
    template <- unname(english[key])
  }
  if (length(template) == 0 || is.na(template)) {
    wf_abort(
      sprintf("Unknown output translation key '%s'.", key),
      "wf_error_internal",
      list(key = key)
    )
  }
  sprintf(template, ...)
}

#' Localize a known report column label.
#'
#' @param name Stable column name.
#' @param lang Optional language selector.
#' @keywords internal
#' @noRd
.wf_i18n_label <- function(name, lang = NULL) {
  language <- .wf_lang(lang)
  key <- paste0("column_", name)
  catalog <- .wf_i18n_catalog(language)
  english <- .wf_i18n_catalog("en")
  if (key %in% union(names(catalog), names(english))) {
    return(.wf_tr(key, lang = language))
  }
  gsub("_", " ", name, fixed = TRUE)
}

#' Localize a known report section label.
#'
#' @param name Stable section name.
#' @param lang Optional language selector.
#' @keywords internal
#' @noRd
.wf_i18n_section <- function(name, lang = NULL) {
  language <- .wf_lang(lang)
  key <- paste0("section_", name)
  catalog <- .wf_i18n_catalog(language)
  english <- .wf_i18n_catalog("en")
  if (key %in% union(names(catalog), names(english))) {
    return(.wf_tr(key, lang = language))
  }
  gsub("_", " ", name, fixed = TRUE)
}
