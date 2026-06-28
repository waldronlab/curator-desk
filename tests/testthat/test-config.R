# Tests for R/config.R - assumes R/config.R is already sourced
# (see tests/testthat.R).

test_that("safe_col replaces spaces with underscores", {
  expect_equal(safe_col("Host Species Status"), "Host_Species_Status")
  expect_equal(safe_col("NoSpaces"), "NoSpaces")
})

test_that("STATUS_COLUMNS has exactly 5 fields (Taxa Level intentionally excluded)", {
  # Taxa Level is deliberately excluded from the curator-desk CSV/feedback
  # schema (see CLAUDE.md / the Milestone 1 fix this regression-tests).
  expect_equal(length(STATUS_COLUMNS), 5)
  expect_false(any(grepl("Taxa", STATUS_COLUMNS)))
})

test_that("feedback_schema produces base + 3 prefixed blocks for each status column", {
  schema <- feedback_schema()
  expect_equal(
    length(schema),
    length(FEEDBACK_BASE_COLS) + 3 * length(STATUS_COLUMNS)
  )
  expect_true(all(paste0("pred__", safe_col(STATUS_COLUMNS)) %in% schema))
  expect_true(all(paste0("true__", safe_col(STATUS_COLUMNS)) %in% schema))
  expect_true(all(paste0("col_feedback__", safe_col(STATUS_COLUMNS)) %in% schema))
})

test_that("feedback_schema never includes a Taxa Level column", {
  expect_false(any(grepl("Taxa", feedback_schema())))
})
