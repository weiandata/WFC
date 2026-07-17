# Pin the default report language so the suite does not depend on the
# session locale of the machine running it. Tests that assert localized
# output pass `lang` explicitly, and the locale-resolution tests in
# test-i18n.R override this option themselves.
options(wfc.lang = "en")
