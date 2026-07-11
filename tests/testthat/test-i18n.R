with_language_environment <- function(code, language = "", lang = "") {
  old_options <- options(wfc.lang = NULL)
  old_language <- Sys.getenv("LANGUAGE", unset = NA_character_)
  old_lang <- Sys.getenv("LANG", unset = NA_character_)
  on.exit({
    options(old_options)
    if (is.na(old_language)) Sys.unsetenv("LANGUAGE") else
      Sys.setenv(LANGUAGE = old_language)
    if (is.na(old_lang)) Sys.unsetenv("LANG") else Sys.setenv(LANG = old_lang)
  }, add = TRUE)
  Sys.setenv(LANGUAGE = language, LANG = lang)
  force(code)
}

test_that("English and Simplified Chinese catalogs have identical keys", {
  english <- .wf_i18n_catalog("en")
  chinese <- .wf_i18n_catalog("zh_CN")

  expect_type(english, "character")
  expect_type(chinese, "character")
  expect_setequal(names(english), names(chinese))
  expect_true(all(nzchar(english)))
  expect_true(all(nzchar(chinese)))
})

test_that("language aliases normalize to stable catalog names", {
  expect_identical(.wf_lang("en"), "en")
  expect_identical(.wf_lang("en_US"), "en")
  expect_identical(.wf_lang("en-GB"), "en")
  expect_identical(.wf_lang("zh"), "zh_CN")
  expect_identical(.wf_lang("zh_CN"), "zh_CN")
  expect_identical(.wf_lang("zh-CN"), "zh_CN")

  expect_error(.wf_lang("fr"), class = "wf_error_input")
  expect_error(.wf_lang(c("en", "zh")), class = "wf_error_input")
})

test_that("explicit language overrides options and options override locale", {
  old <- options(wfc.lang = "zh_CN")
  on.exit(options(old), add = TRUE)

  expect_identical(.wf_lang(), "zh_CN")
  expect_identical(.wf_lang("en"), "en")

  options(wfc.lang = "unsupported")
  expect_error(.wf_lang(), class = "wf_error_input")
})

test_that("session locale resolves Chinese and otherwise falls back to English", {
  with_language_environment({
    expect_identical(.wf_lang(), "zh_CN")
  }, language = "zh_CN", lang = "C")

  with_language_environment({
    expect_identical(.wf_lang(), "en")
  }, language = "", lang = "fr_FR.UTF-8")
})

test_that("translations interpolate and preserve stable keys", {
  chinese_catalog <- .wf_i18n_catalog("zh_CN")

  expect_identical(.wf_tr("report_title", lang = "en"), "Weighting quality report")
  expect_identical(
    .wf_tr("report_title", lang = "zh_CN"),
    unname(chinese_catalog["report_title"])
  )

  english <- .wf_tr("autoweigh_start", 80, 2, 2, lang = "en")
  chinese <- .wf_tr("autoweigh_start", 80, 2, 2, lang = "zh_CN")
  expect_match(english, "80 rows", fixed = TRUE)
  expect_match(chinese, "80", fixed = TRUE)
  expect_false(identical(english, chinese))

  expect_error(.wf_tr("missing_translation_key", lang = "en"),
               class = "wf_error_internal")
})

test_that("known column and section labels localize without changing names", {
  chinese_catalog <- .wf_i18n_catalog("zh_CN")

  expect_identical(.wf_i18n_label("group", "en"), "Group")
  expect_identical(
    .wf_i18n_label("group", "zh_CN"),
    unname(chinese_catalog["column_group"])
  )
  expect_identical(
    .wf_i18n_section("propensity_balance", "zh_CN"),
    unname(chinese_catalog["section_propensity_balance"])
  )
  expect_identical(.wf_i18n_label("unknown_field", "zh_CN"), "unknown field")
})
