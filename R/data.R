# Data loading and normalization (aligned with curator_table/app.py)
# Assumes config.R is loaded (STATUS_COLUMNS, VALID_STATES, etc.)

#' Normalize status string to ABSENT | PARTIALLY_PRESENT | PRESENT
normalize_status <- function(x) {
  if (is.na(x) || length(x) == 0) return("")
  x <- toupper(trimws(as.character(x)))
  if (x %in% VALID_STATES) return(x)
  if (x %in% c("PARTIAL", "PARTIALLY", "PARTLY")) return("PARTIALLY_PRESENT")
  if (x %in% c("YES", "TRUE")) return("PRESENT")
  if (x %in% c("NO", "FALSE")) return("ABSENT")
  x
}

#' Priority score: PRESENT = 1.0, PARTIALLY_PRESENT = 0.5
priority_score <- function(row) {
  score <- 0
  for (col in STATUS_COLUMNS) {
    if (!col %in% names(row)) next
    val <- toupper(trimws(as.character(row[col])))
    if (val == "PRESENT") score <- score + 1 else if (val == "PARTIALLY_PRESENT") score <- score + 0.5
  }
  score
}

#' PubMed URL for a PMID
pmid_link <- function(pmid) {
  p <- tryCatch(as.integer(as.numeric(pmid)), error = function(e) NA)
  if (is.na(p)) return("")
  sprintf("https://pubmed.ncbi.nlm.nih.gov/%s/", p)
}

#' Load CSV or Parquet from path or URL; returns empty data.frame on failure
load_data <- function(path) {
  if (!length(path) || !nzchar(trimws(path))) return(data.frame())
  path <- trimws(path)
  is_url <- grepl("^https?://", path)
  if (!is_url && !file.exists(path))
    return(data.frame())
  ext <- tolower(tools::file_ext(gsub("\\?.*", "", path)))
  if (ext == "csv") {
    tryCatch(
      read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) data.frame()
    )
  } else if (ext %in% c("parquet", "pq")) {
    if (!requireNamespace("arrow", quietly = TRUE))
      stop("Install package 'arrow' to read Parquet files.")
    tryCatch(
      as.data.frame(arrow::read_parquet(path)),
      error = function(e) data.frame()
    )
  } else {
    data.frame()
  }
}

#' Normalize dataset: PMID, status columns, year, priority score, PubMed link
normalize_dataset <- function(df) {
  if (!nrow(df)) return(df)
  if (!"PMID" %in% names(df)) return(data.frame())
  df$PMID <- tryCatch(
    as.integer(as.numeric(df$PMID)),
    warning = function(e) NA,
    error = function(e) NA
  )
  df <- df[!is.na(df$PMID), , drop = FALSE]
  if (!nrow(df)) return(df)
  if (!"Year" %in% names(df) && "Publication Date" %in% names(df)) {
    df$Year <- tryCatch(
      as.integer(format(as.Date(df[["Publication Date"]], optional = TRUE), "%Y")),
      error = function(e) NA_integer_
    )
  }
  for (col in STATUS_COLUMNS) {
    if (col %in% names(df))
      df[[col]] <- vapply(df[[col]], normalize_status, character(1))
  }
  df$"Priority Score" <- apply(df, 1, priority_score)
  df$"PubMed Link" <- vapply(df$PMID, pmid_link, character(1))
  df
}
