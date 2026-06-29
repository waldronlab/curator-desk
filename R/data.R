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

#' Priority score: PRESENT = 1.0, PARTIALLY_PRESENT = 0.5; sum over STATUS_COLUMNS.
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

#' Guard against SSRF when CURATOR_DATA_URL/CURATOR_DATA_PATH points at a
#' URL (mirrors the Python side's app/utils/url_safety.py - that one does a
#' real DNS resolution + IP classification; base R has no portable,
#' dependency-free equivalent, so this is a hostname-pattern check instead.
#' Narrower than the Python guard (a DNS-rebinding host wouldn't be caught)
#' but still blocks the obvious cases, and the threat model here is lower:
#' this URL comes from an operator-set env var, not a live request param.
assert_public_host <- function(url) {
  host <- sub("^https?://([^/:]+).*$", "\\1", url, ignore.case = TRUE)
  if (!nzchar(host) || identical(host, url))
    stop("Could not parse hostname from URL: ", url)
  host_lower <- tolower(host)
  private_patterns <- c(
    "^localhost$", "^127\\.", "^10\\.", "^192\\.168\\.",
    "^172\\.(1[6-9]|2[0-9]|3[0-1])\\.",
    "^169\\.254\\.", "^0\\.0\\.0\\.0$", "^\\[?::1\\]?$",
    "\\.local$", "^metadata\\.google\\.internal$"
  )
  if (any(vapply(private_patterns, grepl, logical(1), x = host_lower))) {
    stop("Refusing to fetch from non-public host: ", host)
  }
  invisible(TRUE)
}

#' Load CSV or Parquet from path or URL; returns empty data.frame on failure
load_data <- function(path) {
  if (!length(path) || !nzchar(trimws(path))) return(data.frame())
  path <- trimws(path)
  is_url <- grepl("^https?://", path)
  if (is_url) {
    ok <- tryCatch({
      assert_public_host(path)
      TRUE
    }, error = function(e) {
      message("Refusing to load ", path, ": ", conditionMessage(e))
      FALSE
    })
    if (!ok) return(data.frame())
  }
  if (!is_url && !file.exists(path))
    return(data.frame())
  ext <- tolower(tools::file_ext(gsub("\\?.*", "", path)))
  if (ext == "csv") {
    tryCatch(
      read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) {
        message("Failed to load ", path, ": ", conditionMessage(e))
        data.frame()
      }
    )
  } else if (ext %in% c("parquet", "pq")) {
    if (!requireNamespace("arrow", quietly = TRUE))
      stop("Install package 'arrow' to read Parquet files.")
    tryCatch(
      as.data.frame(arrow::read_parquet(path)),
      error = function(e) {
        message("Failed to load ", path, ": ", conditionMessage(e))
        data.frame()
      }
    )
  } else {
    data.frame()
  }
}

#' Normalize dataset: PMID, status columns, year, priority score, PubMed link
normalize_dataset <- function(df) {
  if (!nrow(df)) return(df)
  if (!"PMID" %in% names(df)) return(data.frame())
  # suppressWarnings(), not tryCatch(warning = ...): a tryCatch warning
  # handler replaces the *entire* vectorized result with a single NA the
  # moment any one element fails to parse (as.numeric() warns once per
  # call, not per element) - that previously dropped every row whenever a
  # single PMID was malformed, instead of just that row.
  df$PMID <- suppressWarnings(as.integer(as.numeric(df$PMID)))
  df <- df[!is.na(df$PMID), , drop = FALSE]
  if (!nrow(df)) return(df)
  # PMID is the table's primary key (one row per PMID) - keep the first
  # occurrence and drop the rest if the input CSV has duplicates.
  dupe_mask <- duplicated(df$PMID)
  if (any(dupe_mask)) {
    warning(
      sprintf(
        "Dropped %d duplicate-PMID row(s); keeping the first occurrence of each PMID.",
        sum(dupe_mask)
      )
    )
    df <- df[!dupe_mask, , drop = FALSE]
  }
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

  for (col in BOOLEAN_COLUMNS) {
    if (col %in% names(df)) {
      normalized <- toupper(trimws(as.character(df[[col]])))
      df[[col]] <- normalized %in% c("TRUE", "T", "1", "YES")
    } else {
      df[[col]] <- FALSE
    }
  }

  if ("differential_abundance_confidence" %in% names(df)) {
    df$differential_abundance_confidence <- suppressWarnings(
      as.numeric(df$differential_abundance_confidence)
    )
    df$differential_abundance_confidence[is.na(df$differential_abundance_confidence)] <- 0.0
  } else {
    df$differential_abundance_confidence <- 0.0
  }

  if ("Year" %in% names(df)) {
    df$Year <- suppressWarnings(as.integer(df$Year))
  }

  # Vectorized equivalent of apply(df, 1, priority_score): STATUS_COLUMNS
  # are already normalized to PRESENT/PARTIALLY_PRESENT/ABSENT above, so
  # there's no need to re-coerce/re-parse each cell per row via apply()
  # (which also coerces the whole data.frame to a character matrix first).
  score_cols <- STATUS_COLUMNS[STATUS_COLUMNS %in% names(df)]
  if (length(score_cols)) {
    weights <- vapply(score_cols, function(col) {
      ifelse(df[[col]] == "PRESENT", 1,
             ifelse(df[[col]] == "PARTIALLY_PRESENT", 0.5, 0))
    }, numeric(nrow(df)))
    df$Priority <- if (is.matrix(weights)) rowSums(weights) else sum(weights)
  } else {
    df$Priority <- 0
  }
  df$`PubMed Link` <- paste0(
    "<a href='https://pubmed.ncbi.nlm.nih.gov/", df$PMID,
    "/' target='_blank'>", df$PMID, "</a>"
  )
  df
}
