# Data loading and normalization (Curator Desk specification §6.4, §3.2)

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

#' Completeness score: PRESENT = 1.0, PARTIALLY_PRESENT = 0.5 (spec §6.4, max 5.0)
priority_score <- function(row) {
  score <- 0
  for (col in STATUS_COLUMNS) {
    if (!col %in% names(row)) next
    val <- toupper(trimws(as.character(row[[col]])))
    if (val == "PRESENT") score <- score + 1
    else if (val == "PARTIALLY_PRESENT") score <- score + 0.5
  }
  score
}

#' Confidence-weighted priority (long-term vision: weight by ontology mapping confidence)
weighted_priority_score <- function(row) {
  score <- 0
  for (i in seq_along(STATUS_COLUMNS)) {
    status_col <- STATUS_COLUMNS[[i]]
    if (!status_col %in% names(row)) next
    val <- toupper(trimws(as.character(row[[status_col]])))
    base <- if (val == "PRESENT") 1 else if (val == "PARTIALLY_PRESENT") 0.5 else 0
    if (base == 0) next
    conf <- 1.0
    if (i <= length(MAPPING_CONFIDENCE_COLUMNS)) {
      map_col <- MAPPING_CONFIDENCE_COLUMNS[[i]]
      if (map_col %in% names(row)) {
        conf <- suppressWarnings(as.numeric(row[[map_col]]))
        if (is.na(conf)) conf <- 1.0
      }
    }
    score <- score + base * conf
  }
  # Boost high-confidence differential abundance signal (spec §8.2 combined strategy)
  if ("has_differential_abundance" %in% names(row) &&
      isTRUE(row[["has_differential_abundance"]]) &&
      "differential_abundance_confidence" %in% names(row)) {
    da_conf <- suppressWarnings(as.numeric(row[["differential_abundance_confidence"]]))
    if (!is.na(da_conf) && da_conf > 0) {
      score <- score + 0.25 * da_conf
    }
  }
  round(score, 3)
}

#' PubMed URL for a PMID
pmid_link <- function(pmid) {
  p <- tryCatch(as.integer(as.numeric(pmid)), error = function(e) NA)
  if (is.na(p)) return("")
  sprintf("https://pubmed.ncbi.nlm.nih.gov/%s/", p)
}

#' BugSigDB curation search URL (pre-filled PMID; spec §13.2 near-term)
bugsigdb_curation_url <- function(pmid) {
  p <- tryCatch(as.integer(as.numeric(pmid)), error = function(e) NA)
  if (is.na(p)) return("")
  sprintf("https://bugsigdb.org/w/index.php?search=%s", p)
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

#' Join in_bugsigdb from BugSigDB full_dump when column is missing (spec §3.2)
enrich_in_bugsigdb <- function(df) {
  if (!nrow(df) || "in_bugsigdb" %in% names(df)) return(df)
  pmids <- tryCatch(
    read.csv(BUGSIGDB_DUMP_URL, stringsAsFactors = FALSE)$PMID,
    error = function(e) NULL
  )
  if (is.null(pmids)) {
    df$in_bugsigdb <- FALSE
    return(df)
  }
  bugsig_set <- unique(suppressWarnings(as.integer(pmids)))
  bugsig_set <- bugsig_set[!is.na(bugsig_set)]
  df$in_bugsigdb <- df$PMID %in% bugsig_set
  df
}

#' Normalize dataset: PMID, statuses, booleans, Priority Score, PubMed link
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

  for (col in BOOLEAN_COLUMNS) {
    if (col %in% names(df)) {
      normalized <- toupper(trimws(as.character(df[[col]])))
      df[[col]] <- normalized %in% c("TRUE", "T", "1", "YES")
    } else {
      df[[col]] <- FALSE
    }
  }

  df <- enrich_in_bugsigdb(df)

  if ("differential_abundance_confidence" %in% names(df)) {
    df$differential_abundance_confidence <- suppressWarnings(
      as.numeric(df$differential_abundance_confidence)
    )
    df$differential_abundance_confidence[is.na(df$differential_abundance_confidence)] <- 0.0
  } else {
    df$differential_abundance_confidence <- 0.0
  }

  for (col in MAPPING_CONFIDENCE_COLUMNS) {
    if (col %in% names(df)) {
      df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
      df[[col]][is.na(df[[col]])] <- 0.0
    }
  }

  if ("Year" %in% names(df)) {
    df$Year <- suppressWarnings(as.integer(df$Year))
  }

  df$`Priority Score` <- vapply(seq_len(nrow(df)), function(i) {
    weighted_priority_score(df[i, , drop = FALSE])
  }, numeric(1))

  # Backward compatibility for older builds referencing "Priority"
  df$Priority <- df$`Priority Score`

  df$`PubMed Link` <- paste0(
    "<a href='https://pubmed.ncbi.nlm.nih.gov/", df$PMID,
    "/' target='_blank'>", df$PMID, "</a>"
  )
  df$`BugSigDB Link` <- vapply(df$PMID, function(p) {
    url <- bugsigdb_curation_url(p)
    if (!nzchar(url)) return("")
    sprintf("<a href='%s' target='_blank'>Curate</a>", url)
  }, character(1))

  df
}
