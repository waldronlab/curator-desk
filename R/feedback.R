# Feedback persistence and row builder (aligned with curator_table/app.py)
# load_feedback / save_feedback / upsert_feedback for local or Shiny use;
# static GitHub Pages uses JS + CSV download only.

#' Load feedback from parquet then csv; empty data.frame with schema if missing
load_feedback <- function() {
  schema <- feedback_schema()
  if (file.exists(FEEDBACK_PARQUET) && requireNamespace("arrow", quietly = TRUE)) {
    tryCatch(
      return(as.data.frame(arrow::read_parquet(FEEDBACK_PARQUET))),
      error = function(e) message("Failed to load ", FEEDBACK_PARQUET, ": ", e)
    )
  }
  if (file.exists(FEEDBACK_CSV)) {
    tryCatch(
      return(read.csv(FEEDBACK_CSV, stringsAsFactors = FALSE)),
      error = function(e) message("Failed to load ", FEEDBACK_CSV, ": ", e)
    )
  }
  as.data.frame(matrix(character(0), nrow = 0, ncol = length(schema),
                       dimnames = list(NULL, schema)), stringsAsFactors = FALSE)
}

#' Persist feedback to CSV and Parquet; ensure schema columns exist
save_feedback <- function(df) {
  dir.create(CONFIG$feedback_dir, showWarnings = FALSE, recursive = TRUE)
  schema <- feedback_schema()
  for (col in schema) {
    if (!col %in% names(df)) df[[col]] <- ""
  }
  write.csv(df, FEEDBACK_CSV, row.names = FALSE)
  if (requireNamespace("arrow", quietly = TRUE)) {
    tryCatch(
      arrow::write_parquet(df, FEEDBACK_PARQUET),
      error = function(e) message("Parquet save skipped: ", e)
    )
  }
  invisible(NULL)
}

#' Upsert one row by PMID + curator_id
upsert_feedback <- function(existing, row) {
  schema <- feedback_schema()
  for (col in schema) {
    if (!col %in% names(existing)) existing[[col]] <- ""
  }
  if (nrow(existing) > 0) {
    match_pmid <- (as.character(existing[["PMID"]]) == as.character(row[["PMID"]]))
    match_curator <- (as.character(existing[["curator_id"]]) == as.character(row[["curator_id"]]))
    mask <- match_pmid & match_curator
    if (any(mask)) {
      for (k in names(row)) {
        if (k %in% names(existing)) existing[[k]][mask] <- row[[k]]
      }
      return(existing)
    }
  }
  new_row <- as.data.frame(row, stringsAsFactors = FALSE)
  for (col in schema) {
    if (!col %in% names(new_row)) new_row[[col]] <- ""
  }
  new_row <- new_row[, schema, drop = FALSE]
  rbind(existing, new_row)
}

#' Build one feedback row as a named character vector (all columns in schema)
feedback_row <- function(pmid, curator_id, overall_verdict, comment,
                        bioanalyzer_version, pred_values, true_values, col_feedback_values) {
  schema <- feedback_schema()
  row <- setNames(rep("", length(schema)), schema)
  row["PMID"] <- as.character(pmid)
  row["curator_id"] <- as.character(curator_id)
  row["overall_verdict"] <- as.character(overall_verdict)
  row["comment"] <- as.character(comment)
  row["timestamp"] <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  row["bioanalyzer_version"] <- as.character(bioanalyzer_version)
  for (col in STATUS_COLUMNS) {
    s <- safe_col(col)
    row[paste0(PRED_PREFIX, s)] <- if (col %in% names(pred_values)) as.character(pred_values[[col]]) else ""
    row[paste0(TRUE_PREFIX, s)] <- if (paste0(TRUE_PREFIX, s) %in% names(true_values)) as.character(true_values[[paste0(TRUE_PREFIX, s)]]) else "Not reviewed"
    row[paste0(COL_FB_PREFIX, s)] <- if (paste0(COL_FB_PREFIX, s) %in% names(col_feedback_values)) as.character(col_feedback_values[[paste0(COL_FB_PREFIX, s)]]) else "Not reviewed"
  }
  row
}

#' Convert one feedback row to CSV string (header + one row)
feedback_row_to_csv <- function(row) {
  schema <- feedback_schema()
  row <- row[match(schema, names(row))]
  paste0(paste(names(row), collapse = ","), "\n", paste(row, collapse = ","), "\n")
}
