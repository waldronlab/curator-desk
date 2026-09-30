# Tests for R/config.R - assumes R/config.R is already sourced
# (see tests/testthat.R).

test_that("safe_col replaces spaces with underscores", {
  expect_equal(safe_col("Host Species Status"), "Host_Species_Status")
  expect_equal(safe_col("NoSpaces"), "NoSpaces")
})

test_that("VALUE_COLUMNS has exactly 5 fields (Taxa Level intentionally excluded)", {
  # Taxa Level is deliberately excluded from the curator-desk CSV/feedback
  # schema (see CLAUDE.md / docs/CURATOR_DESK_CSV_FORMAT.md in the parent repo).
  expect_equal(length(VALUE_COLUMNS), 5)
  expect_false(any(grepl("Taxa", VALUE_COLUMNS)))
})

test_that("ONTOLOGY_ID_COLUMNS has exactly 3 fields, one per external ontology", {
  # Sequencing Type and Sample Size have no external ontology mapping.
  expect_equal(length(ONTOLOGY_ID_COLUMNS), 3)
  expect_true(all(grepl("Ontology ID$", ONTOLOGY_ID_COLUMNS)))
})

test_that("feedback_schema produces base + 3 value blocks + 2 ontology blocks", {
  schema <- feedback_schema()
  expect_equal(
    length(schema),
    length(FEEDBACK_BASE_COLS) + 3 * length(VALUE_COLUMNS) + 2 * length(ONTOLOGY_ID_COLUMNS)
  )
  expect_true(all(paste0("pred__", safe_col(VALUE_COLUMNS)) %in% schema))
  expect_true(all(paste0("true__", safe_col(VALUE_COLUMNS)) %in% schema))
  expect_true(all(paste0("col_feedback__", safe_col(VALUE_COLUMNS)) %in% schema))
  expect_true(all(paste0("pred__", safe_col(ONTOLOGY_ID_COLUMNS)) %in% schema))
  expect_true(all(paste0("true__", safe_col(ONTOLOGY_ID_COLUMNS)) %in% schema))
  # No col_feedback__ triplet for ontology ID columns - only value fields
  # get the "was BioAnalyzer correct?" dropdown.
  expect_false(any(paste0("col_feedback__", safe_col(ONTOLOGY_ID_COLUMNS)) %in% schema))
})

test_that("feedback_schema never includes a Taxa Level column", {
  expect_false(any(grepl("Taxa", feedback_schema())))
})

test_that("SEQUENCING_TYPE_VALUES are BugSigDB's own Sequencing type values", {
  expect_equal(SEQUENCING_TYPE_VALUES, c("16S", "18S", "WMS", "ITS / ITS2", "PCR"))
})

test_that("curator_value_input_html gives Sequencing Type a checkbox per BugSigDB value", {
  html <- curator_value_input_html("Sequencing Type")
  expect_match(html, 'id="true_Sequencing_Type" class="cd-choice-group"', fixed = TRUE)
  values <- regmatches(html, gregexpr('(?<=type="checkbox" value=")[^"]+', html, perl = TRUE))[[1]]
  expect_equal(values, SEQUENCING_TYPE_VALUES)
  expect_false(grepl('type="text"', html, fixed = TRUE))
})

test_that("curator_value_input_html keeps a text box for every other field", {
  for (col in setdiff(VALUE_COLUMNS, "Sequencing Type")) {
    expect_equal(
      curator_value_input_html(col),
      sprintf('<input type="text" id="true_%s" class="form-control">', safe_col(col))
    )
  }
})
