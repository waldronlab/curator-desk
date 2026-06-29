# Tests for R/data.R - assumes R/config.R and R/data.R are already sourced
# (see tests/testthat.R).

test_that("assert_public_host blocks private/loopback/link-local hosts", {
  expect_error(assert_public_host("http://localhost:8080/data.csv"))
  expect_error(assert_public_host("http://127.0.0.1/admin"))
  expect_error(assert_public_host("http://169.254.169.254/latest/meta-data/"))
  expect_error(assert_public_host("http://192.168.1.1/data.csv"))
  expect_error(assert_public_host("http://10.0.0.5/data.csv"))
  expect_error(assert_public_host("http://172.16.0.1/data.csv"))
  expect_error(assert_public_host("http://internal.local/data.csv"))
  expect_error(assert_public_host("http://metadata.google.internal/"))
})

test_that("assert_public_host allows ordinary public hosts", {
  expect_true(assert_public_host("https://raw.githubusercontent.com/org/repo/main/data.csv"))
  expect_true(assert_public_host("https://example.com/data.csv"))
})

test_that("load_data refuses to fetch from a private-host URL", {
  expect_message(
    df <- load_data("http://127.0.0.1/data.csv"),
    "Refusing to load"
  )
  expect_equal(nrow(df), 0)
})

test_that("normalize_status passes through valid states unchanged", {
  expect_equal(normalize_status("PRESENT"), "PRESENT")
  expect_equal(normalize_status("ABSENT"), "ABSENT")
  expect_equal(normalize_status("PARTIALLY_PRESENT"), "PARTIALLY_PRESENT")
})

test_that("normalize_status is case- and whitespace-insensitive", {
  expect_equal(normalize_status(" present "), "PRESENT")
  expect_equal(normalize_status("absent"), "ABSENT")
})

test_that("normalize_status maps known synonyms to canonical states", {
  expect_equal(normalize_status("partial"), "PARTIALLY_PRESENT")
  expect_equal(normalize_status("partly"), "PARTIALLY_PRESENT")
  expect_equal(normalize_status("yes"), "PRESENT")
  expect_equal(normalize_status("true"), "PRESENT")
  expect_equal(normalize_status("no"), "ABSENT")
  expect_equal(normalize_status("false"), "ABSENT")
})

test_that("normalize_status returns unrecognized input unchanged", {
  expect_equal(normalize_status("weird_value"), "WEIRD_VALUE")
})

test_that("normalize_status handles NA and empty input", {
  expect_equal(normalize_status(NA), "")
  expect_equal(normalize_status(character(0)), "")
})

test_that("priority_score sums 1.0 for PRESENT and 0.5 for PARTIALLY_PRESENT", {
  row <- list(
    "Host Species Status" = "PRESENT",
    "Body Site Status" = "PARTIALLY_PRESENT",
    "Condition Status" = "ABSENT",
    "Sequencing Type Status" = "PRESENT",
    "Sample Size Status" = "PARTIALLY_PRESENT"
  )
  expect_equal(priority_score(row), 1 + 0.5 + 0 + 1 + 0.5)
})

test_that("priority_score ignores columns missing from the row", {
  row <- list("Host Species Status" = "PRESENT")
  expect_equal(priority_score(row), 1)
})

test_that("priority_score returns 0 for an empty/all-ABSENT row", {
  row <- list(
    "Host Species Status" = "ABSENT",
    "Body Site Status" = "ABSENT"
  )
  expect_equal(priority_score(row), 0)
})

test_that("pmid_link builds a PubMed URL for a valid PMID", {
  expect_equal(
    pmid_link("12345678"),
    "https://pubmed.ncbi.nlm.nih.gov/12345678/"
  )
  expect_equal(pmid_link(12345678), "https://pubmed.ncbi.nlm.nih.gov/12345678/")
})

test_that("pmid_link returns empty string for invalid PMID", {
  # as.numeric() on unparseable input emits a benign "NAs introduced by
  # coercion" warning that pmid_link()'s own tryCatch already handles.
  expect_equal(suppressWarnings(pmid_link("not-a-number")), "")
  expect_equal(pmid_link(NA), "")
})

test_that("load_data returns empty data.frame for a missing path", {
  df <- load_data("/no/such/file.csv")
  expect_equal(nrow(df), 0)
})

test_that("load_data returns empty data.frame for blank/NULL path", {
  expect_equal(nrow(load_data("")), 0)
  expect_equal(nrow(load_data(NULL)), 0)
})

test_that("load_data reads a real CSV file", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(
    data.frame(PMID = c(1, 2), Title = c("A", "B")),
    tmp, row.names = FALSE
  )
  df <- load_data(tmp)
  expect_equal(nrow(df), 2)
  expect_equal(df$PMID, c(1, 2))
})

test_that("load_data falls back to empty data.frame on malformed CSV", {
  # A directory named *.csv passes the path/extension checks but can't be
  # opened by read.csv() as a file - reliably exercises the error branch
  # (read.csv() is otherwise very lenient about malformed file contents).
  tmp_dir <- tempfile(fileext = ".csv")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))
  expect_message(
    df <- suppressWarnings(load_data(tmp_dir)),
    "Failed to load"
  )
  expect_equal(nrow(df), 0)
})

test_that("normalize_dataset drops rows with non-numeric PMID", {
  df <- data.frame(
    PMID = c("123", "not-a-pmid", "456"),
    stringsAsFactors = FALSE
  )
  result <- normalize_dataset(df)
  expect_equal(sort(result$PMID), c(123, 456))
})

test_that("normalize_dataset keeps one row per PMID, preferring the first occurrence", {
  df <- data.frame(
    PMID = c("123", "456", "123"),
    Title = c("First version", "Other paper", "Duplicate version"),
    stringsAsFactors = FALSE
  )
  expect_warning(
    result <- normalize_dataset(df),
    "duplicate-PMID"
  )
  expect_equal(nrow(result), 2)
  expect_equal(sort(result$PMID), c(123, 456))
  expect_equal(result$Title[result$PMID == 123], "First version")
})

test_that("normalize_dataset returns empty data.frame when PMID column is missing", {
  df <- data.frame(Title = c("A", "B"), stringsAsFactors = FALSE)
  result <- normalize_dataset(df)
  expect_equal(nrow(result), 0)
})

test_that("normalize_dataset returns input unchanged when already empty", {
  df <- data.frame()
  expect_equal(nrow(normalize_dataset(df)), 0)
})

test_that("normalize_dataset normalizes status columns and computes Priority", {
  df <- data.frame(
    PMID = c("1"),
    `Host Species Status` = "present",
    `Body Site Status` = "partial",
    `Condition Status` = "absent",
    `Sequencing Type Status` = "PRESENT",
    `Sample Size Status` = "PRESENT",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  result <- normalize_dataset(df)
  expect_equal(result$`Host Species Status`, "PRESENT")
  expect_equal(result$`Body Site Status`, "PARTIALLY_PRESENT")
  expect_equal(result$`Condition Status`, "ABSENT")
  expect_equal(result$Priority, 1 + 0.5 + 0 + 1 + 1)
})

test_that("normalize_dataset defaults missing boolean columns to FALSE", {
  df <- data.frame(PMID = c("1"), stringsAsFactors = FALSE)
  result <- normalize_dataset(df)
  expect_false(result$has_differential_abundance)
  expect_false(result$in_bugsigdb)
})

test_that("normalize_dataset coerces boolean-like strings correctly", {
  df <- data.frame(
    PMID = c("1", "2"),
    has_differential_abundance = c("TRUE", "no"),
    in_bugsigdb = c("yes", "0"),
    stringsAsFactors = FALSE
  )
  result <- normalize_dataset(df)
  expect_equal(result$has_differential_abundance, c(TRUE, FALSE))
  expect_equal(result$in_bugsigdb, c(TRUE, FALSE))
})

test_that("normalize_dataset builds a PubMed Link column from PMID", {
  df <- data.frame(PMID = c("12345678"), stringsAsFactors = FALSE)
  result <- normalize_dataset(df)
  expect_true(grepl("12345678", result$`PubMed Link`))
  expect_true(grepl("pubmed.ncbi.nlm.nih.gov", result$`PubMed Link`))
})
