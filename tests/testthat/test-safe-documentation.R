safe_documentation_section <- function(text) {
  start <- grep("<!-- SAFE_WORKFLOW_START -->", text, fixed = TRUE)
  end <- grep("<!-- SAFE_WORKFLOW_END -->", text, fixed = TRUE)
  if (length(start) != 1L || length(end) != 1L || start >= end) {
    return(character())
  }
  text[seq.int(start + 1L, end - 1L)]
}

test_that("safe workflow documentation covers every controlled step", {
  root <- normalizePath(test_path("..", ".."), mustWork = FALSE)
  paths <- file.path(
    root,
    c("README.md", "README.zh-CN.md", "vignettes/safe-weighting-workflow.Rmd")
  )
  all_present <- all(file.exists(paths))
  skip_if_not(all_present, "complete source documentation set is not installed")
  expect_true(all_present)
  required <- c(
    "wf_prepare_design(",
    "wf_import_target(",
    "wf_plan_weights(",
    "wf_approve_plan(",
    "wf_execute_plan(",
    "wf_attach_weights(",
    "wf_report("
  )

  for (path in paths) {
    text <- readLines(path, warn = FALSE)
    section <- safe_documentation_section(text)
    expect_gt(length(section), 0)
    joined <- paste(section, collapse = "\n")
    expect_true(all(vapply(
      required,
      grepl,
      logical(1),
      x = joined,
      fixed = TRUE
    )))
    expect_false(grepl("wf_target_manual(", joined, fixed = TRUE))
    expect_false(grepl("moments =", joined, fixed = TRUE))
  }
})

test_that("safe documentation includes import files and agent refusal contract", {
  root <- normalizePath(test_path("..", ".."), mustWork = FALSE)
  paths <- file.path(
    root,
    c(
      "README.md",
      "README.zh-CN.md",
      "examples/README.md",
      "vignettes/safe-weighting-workflow.Rmd"
    )
  )
  all_present <- all(file.exists(paths))
  skip_if_not(all_present, "complete source documentation set is not installed")
  expect_true(all_present)
  joined <- paste(unlist(lapply(paths, readLines, warn = FALSE)), collapse = "\n")

  expect_match(joined, "safe-target-example.csv", fixed = TRUE)
  expect_match(joined, "safe-target-example.xlsx", fixed = TRUE)
  expect_match(joined, ".source.dcf", fixed = TRUE)
  expect_match(joined, "wf_error_safety", fixed = TRUE)
  expect_match(joined, "next_actions", fixed = TRUE)
  expect_match(joined, "actor_type = \"agent\"", fixed = TRUE)
  expect_match(joined, "wf_assess_impact(", fixed = TRUE)
  expect_match(joined, "wf_audit_export(", fixed = TRUE)
})

test_that("all current user documentation excludes removed weighting paths", {
  root <- normalizePath(test_path("..", ".."), mustWork = FALSE)
  paths <- c(
    file.path(root, "README.md"),
    file.path(root, "README.zh-CN.md"),
    list.files(
      file.path(root, "examples"),
      pattern = "[.](md|R|Rmd)$",
      full.names = TRUE
    ),
    list.files(
      file.path(root, "vignettes"),
      pattern = "[.](md|R|Rmd)$",
      full.names = TRUE
    )
  )
  paths <- paths[file.exists(paths)]
  skip_if(length(paths) == 0L, "source documentation is not installed")

  forbidden <- c(
    "wf_target_manual(",
    "wf_target_shrink(",
    "moments =",
    "mode = \"manual\"",
    "mode = 'manual'",
    "wf_run(..., margins ="
  )
  for (path in paths) {
    text <- paste(readLines(path, warn = FALSE), collapse = "\n")
    for (pattern in forbidden) {
      expect_false(
        grepl(pattern, text, fixed = TRUE),
        info = sprintf("%s still contains %s", basename(path), pattern)
      )
    }
  }
})

test_that("migration examples use executable safe import and report forms", {
  root <- normalizePath(test_path("..", ".."), mustWork = FALSE)
  path <- file.path(root, "docs", "migration", "wfc-1-to-2.md")
  skip_if_not(file.exists(path), "migration guide is not installed")
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")

  expect_false(grepl("wf_report(weights, target", text, fixed = TRUE))
  expect_false(grepl(
    "source_file = \"population-source.pdf\"",
    text,
    fixed = TRUE
  ))
  expect_match(text, "population-source.dcf", fixed = TRUE)
})
