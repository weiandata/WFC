.wf_source_fields <- c(
  "publisher",
  "dataset_title",
  "citation",
  "reference_period",
  "population_scope",
  "retrieved_at",
  "license",
  "checksum_algorithm",
  "checksum",
  "transformation",
  "selected_before_outcomes",
  "demo_only"
)

#' Read a CSV or Excel target table.
#'
#' @param path Path to the target table.
#' @keywords internal
#' @noRd
.wf_read_target_table <- function(path) {
  if (!.wf_is_string(path) || !file.exists(path)) {
    .wf_safety_abort(
      "source_file_missing",
      "Target data file does not exist.",
      "data_file"
    )
  }

  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") {
    return(utils::read.csv(path, stringsAsFactors = FALSE))
  }
  if (ext == "xlsx") {
    if (!requireNamespace("openxlsx", quietly = TRUE)) {
      wf_abort(
        "Package 'openxlsx' is required for Excel targets.",
        "wf_error_dependency",
        list(package = "openxlsx")
      )
    }
    return(openxlsx::read.xlsx(path))
  }

  .wf_safety_abort(
    "target_format_unsupported",
    "Target file must be CSV or XLSX.",
    "data_file",
    next_actions = "use_csv_or_xlsx"
  )
}

#' Write a CSV or Excel target table.
#'
#' @param data Target data frame.
#' @param path Output path.
#' @keywords internal
#' @noRd
.wf_write_target_table <- function(data, path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") {
    utils::write.csv(data, path, row.names = FALSE)
    return(invisible(path))
  }
  if (ext == "xlsx") {
    if (!requireNamespace("openxlsx", quietly = TRUE)) {
      wf_abort(
        "Package 'openxlsx' is required for Excel targets.",
        "wf_error_dependency",
        list(package = "openxlsx")
      )
    }
    openxlsx::write.xlsx(data, path, overwrite = FALSE)
    return(invisible(path))
  }

  .wf_safety_abort(
    "target_format_unsupported",
    "Target file must be CSV or XLSX.",
    "file",
    next_actions = "use_csv_or_xlsx"
  )
}

#' Read and validate target source evidence.
#'
#' @param source_file Path to a one-record DCF source file.
#' @param data_file Path to the target data file described by the source record.
#' @param production Whether demo-only evidence must be rejected.
#' @keywords internal
#' @noRd
.wf_read_source_evidence <- function(source_file, data_file, production) {
  if (!.wf_is_string(source_file) || !file.exists(source_file)) {
    .wf_safety_abort(
      "source_metadata_missing",
      "Target source metadata file does not exist.",
      "source_file",
      next_actions = "supply_source_metadata"
    )
  }
  if (!is.logical(production) || length(production) != 1L || is.na(production)) {
    .wf_safety_abort(
      "production_flag_invalid",
      "`production` must be TRUE or FALSE.",
      "production"
    )
  }

  source <- tryCatch(
    read.dcf(source_file, all = TRUE),
    error = function(e) {
      .wf_safety_abort(
        "source_metadata_invalid",
        "Target source metadata must be a valid DCF file.",
        "source_file",
        evidence = list(reason = conditionMessage(e)),
        next_actions = "repair_source_metadata"
      )
    }
  )
  if (nrow(source) != 1L) {
    .wf_safety_abort(
      "source_metadata_record_count",
      "Target source metadata must contain exactly one record.",
      "source_file",
      evidence = list(records = nrow(source))
    )
  }

  missing <- setdiff(.wf_source_fields, colnames(source))
  empty <- intersect(
    .wf_source_fields,
    colnames(source)[is.na(source[1, ]) | !nzchar(trimws(source[1, ]))]
  )
  if (length(missing) || length(empty)) {
    .wf_safety_abort(
      "source_metadata_incomplete",
      "Target source metadata are incomplete.",
      "source_file",
      evidence = list(missing = missing, empty = empty),
      next_actions = "complete_source_metadata"
    )
  }

  values <- stats::setNames(
    as.character(source[1, .wf_source_fields, drop = TRUE]),
    .wf_source_fields
  )
  algorithm <- tolower(trimws(values[["checksum_algorithm"]]))
  if (!identical(algorithm, "sha256")) {
    .wf_safety_abort(
      "checksum_algorithm_unsupported",
      "Target source checksum algorithm must be SHA-256.",
      "checksum_algorithm"
    )
  }

  computed <- .wf_sha256_file(data_file)
  recorded <- tolower(trimws(values[["checksum"]]))
  if (!grepl("^[0-9a-f]{64}$", recorded) || !identical(recorded, computed)) {
    .wf_safety_abort(
      "source_checksum_mismatch",
      "Target data do not match the recorded SHA-256 checksum.",
      "checksum",
      evidence = list(recorded = recorded, computed = computed),
      next_actions = "verify_target_file"
    )
  }

  parse_flag <- function(name) {
    value <- tolower(trimws(values[[name]]))
    if (!value %in% c("true", "false")) {
      .wf_safety_abort(
        "source_flag_invalid",
        sprintf("Source field '%s' must be true or false.", name),
        name
      )
    }
    identical(value, "true")
  }
  selected_before_outcomes <- parse_flag("selected_before_outcomes")
  demo_only <- parse_flag("demo_only")

  if (!selected_before_outcomes) {
    .wf_safety_abort(
      "target_selected_after_outcomes",
      "The target source must be selected before study outcomes are examined.",
      "selected_before_outcomes",
      next_actions = "use_preselected_external_target"
    )
  }
  if (production && demo_only) {
    .wf_safety_abort(
      "demo_target_in_production",
      "Demo-only target data cannot be used in production.",
      "demo_only",
      next_actions = "supply_authoritative_target"
    )
  }

  list(
    fields = as.list(values),
    data_checksum = computed,
    source_checksum = .wf_sha256_file(source_file),
    selected_before_outcomes = selected_before_outcomes,
    demo_only = demo_only
  )
}

#' Calculate the identity of a verified target.
#'
#' @param target A verified target with evidence fields attached.
#' @keywords internal
#' @noRd
.wf_verified_target_identity <- function(target) {
  .wf_sha256_object(list(
    mode = target$mode,
    by = target$by,
    dims = target$dims,
    groups = target$groups,
    joint = target$joint,
    evidence = target$evidence,
    demo_only = target$demo_only,
    source_type = target$source_type
  ))
}

#' Attach verified source evidence to a target.
#'
#' @param target A `wf_target` object.
#' @param evidence Validated source evidence.
#' @param source_type Source type label.
#' @keywords internal
#' @noRd
.wf_verified_target <- function(target, evidence, source_type) {
  target$evidence <- evidence
  target$demo_only <- evidence$demo_only
  target$source_type <- source_type
  target$identity <- .wf_verified_target_identity(target)
  class(target) <- c("wf_verified_target", "wf_target")
  target
}

#' Create a safe external-target import template
#'
#' Writes a CSV or Excel data template and a separate companion DCF source
#' record. The source filename appends `.source.dcf` to the complete data
#' filename so CSV and Excel files cannot accidentally share a checksum.
#'
#' @param file Output path ending in `.csv` or `.xlsx`.
#' @param dims A `wf_dims` object with declared levels when `example = TRUE`.
#' @param by Optional grouping-column name.
#' @param example Whether to write synthetic, demo-only rows instead of a blank
#'   template.
#'
#' @return Invisibly, a list with `data_file` and `source_file` paths.
#' @export
wf_target_template <- function(file, dims, by = NULL, example = FALSE) {
  if (!.wf_is_string(file)) {
    .wf_safety_abort(
      "target_template_path_invalid",
      "`file` must be one CSV or XLSX path.",
      "file"
    )
  }
  if (!inherits(dims, "wf_dims")) {
    .wf_safety_abort(
      "target_dimensions_invalid",
      "`dims` must be a wf_dims object.",
      "dims"
    )
  }
  if (!is.logical(example) || length(example) != 1L || is.na(example)) {
    .wf_safety_abort(
      "target_template_example_invalid",
      "`example` must be TRUE or FALSE.",
      "example"
    )
  }

  source_file <- paste0(file, ".source.dcf")
  existing <- c(file, source_file)[file.exists(c(file, source_file))]
  if (length(existing)) {
    .wf_safety_abort(
      "target_template_exists",
      "The target template or its source record already exists.",
      "file",
      evidence = list(paths = existing),
      next_actions = "choose_new_template_path"
    )
  }
  if (!dir.exists(dirname(file))) {
    .wf_safety_abort(
      "target_template_directory_missing",
      "The target template directory does not exist.",
      "file",
      evidence = list(directory = dirname(file)),
      next_actions = "create_template_directory"
    )
  }

  dim_names <- names(dims$vars)
  columns <- c(by, dim_names, "count")
  if (example) {
    missing_levels <- dim_names[vapply(dims$vars, is.null, logical(1))]
    if (length(missing_levels)) {
      .wf_safety_abort(
        "target_template_levels_missing",
        "Synthetic examples require declared levels for every dimension.",
        "dims",
        evidence = list(dimensions = missing_levels),
        next_actions = "declare_dimension_levels"
      )
    }
    data <- expand.grid(
      dims$vars,
      KEEP.OUT.ATTRS = FALSE,
      stringsAsFactors = FALSE
    )
    if (!is.null(by)) {
      data[[by]] <- "example_group"
    }
    data$count <- rep(100, nrow(data))
    data <- data[, columns, drop = FALSE]
  } else {
    data <- as.data.frame(
      stats::setNames(
        lapply(columns, function(name) {
          if (identical(name, "count")) numeric() else character()
        }),
        columns
      ),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  }

  .wf_write_target_table(data, file)
  if (example) {
    source <- c(
      publisher = "WFC synthetic example",
      dataset_title = "Synthetic population target example",
      citation = "WFC package synthetic example; not an external authority",
      reference_period = "synthetic",
      population_scope = "synthetic demonstration population",
      retrieved_at = as.character(Sys.Date()),
      license = "CC0-1.0",
      checksum_algorithm = "sha256",
      checksum = .wf_sha256_file(file),
      transformation = "Generated Cartesian example with equal counts",
      selected_before_outcomes = "true",
      demo_only = "true"
    )
  } else {
    source <- c(
      publisher = "",
      dataset_title = "",
      citation = "",
      reference_period = "",
      population_scope = "",
      retrieved_at = "",
      license = "",
      checksum_algorithm = "sha256",
      checksum = .wf_sha256_file(file),
      transformation = "",
      selected_before_outcomes = "false",
      demo_only = "false"
    )
  }
  writeLines(sprintf("%s: %s", names(source), source), source_file)

  invisible(list(data_file = file, source_file = source_file))
}

#' Import a verified external population target
#'
#' Imports CSV or Excel population margins only when a companion DCF record
#' supplies complete provenance and a matching SHA-256 checksum.
#'
#' @param data_file Path to a CSV or XLSX population table.
#' @param source_file Path to its companion source DCF record.
#' @param dims A `wf_dims` object.
#' @param key_map Named mapping from dimensions to data columns.
#' @param count Name of the population-count column.
#' @param by Optional grouping variable.
#' @param by_key Optional group-key column or function.
#' @param production Whether to reject demo-only sources.
#'
#' @return A `wf_verified_target` object.
#' @examples
#' # WFC ships a synthetic demo target beside its companion evidence record.
#' csv_file <- system.file(
#'   "extdata", "safe-target-example.csv",
#'   package = "WFC"
#' )
#' csv_source <- paste0(csv_file, ".source.dcf")
#'
#' dims_safe <- wf_dims(sex = c("F", "M"), age = c("18-34", "35+"))
#'
#' # `production = FALSE` is required here only because the bundled file is
#' # declared demo-only. Do not use it to admit an authoritative source whose
#' # evidence record is incomplete.
#' target <- wf_import_target(
#'   csv_file,
#'   csv_source,
#'   dims_safe,
#'   key_map = c(sex = "sex", age = "age"),
#'   count = "count",
#'   production = FALSE
#' )
#' target$identity
#'
#' # The same demo file is refused as a production source, so a synthetic
#' # file cannot impersonate an authoritative population.
#' try(wf_import_target(
#'   csv_file,
#'   csv_source,
#'   dims_safe,
#'   key_map = c(sex = "sex", age = "age"),
#'   count = "count"
#' ))
#' @export
wf_import_target <- function(data_file, source_file, dims, key_map, count,
                             by = NULL, by_key = NULL, production = TRUE) {
  evidence <- .wf_read_source_evidence(source_file, data_file, production)
  population <- .wf_read_target_table(data_file)
  target <- wf_target_population(
    population,
    key_map = key_map,
    count = count,
    dims = dims,
    by = by,
    by_key = by_key,
    keep_joint = TRUE
  )

  .wf_verified_target(target, evidence, "population")
}

#' Import a verified external reference-sample target
#'
#' Imports an external reference sample only when every file column has a
#' declared design role and the companion DCF record passes the provenance and
#' checksum checks.
#'
#' @param data_file Path to a CSV or XLSX reference sample.
#' @param source_file Path to its companion source DCF record.
#' @param dims A `wf_dims` object.
#' @param feature Name of the reciprocal-design-weight column.
#' @param by Optional grouping variable.
#' @param production Whether to reject demo-only sources.
#'
#' @return A `wf_verified_target` object.
#' @export
wf_import_reference <- function(data_file, source_file, dims, feature,
                                by = NULL, production = TRUE) {
  evidence <- .wf_read_source_evidence(source_file, data_file, production)
  reference <- .wf_read_target_table(data_file)
  allowed <- unique(c(names(dims$vars), feature, by))
  extra <- setdiff(names(reference), allowed)
  if (length(extra)) {
    .wf_safety_abort(
      "reference_columns_unassigned",
      sprintf(
        "Reference data contain unassigned column(s): %s.",
        paste(extra, collapse = ", ")
      ),
      evidence = list(columns = extra),
      next_actions = "remove_outcome_columns"
    )
  }

  .require_cols(reference, allowed, "reference data")
  reference <- reference[, allowed, drop = FALSE]
  target <- wf_target_reference(
    reference,
    feature = feature,
    dims = dims,
    by = by
  )

  .wf_verified_target(target, evidence, "reference")
}
