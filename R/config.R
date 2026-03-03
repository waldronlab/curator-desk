# Schema and options (aligned with curator_table/app.py)
# Used for normalization, feedback column names, and UI options.
# Config: env overrides (same as Python CONFIG)
CONFIG <- list(
  feedback_dir = Sys.getenv("FEEDBACK_DIR", "results"),
  curator_id_default = Sys.getenv("USER", ""),
  bioanalyzer_version_default = Sys.getenv("BIOANALYZER_VERSION", "1.0.0"),
  # Base URL for new issue; JS will append title and body (with CSV in body)
  feedback_issue_url = if (nzchar(trimws(Sys.getenv("GITHUB_REPO", ""))))
    paste0(trimws(Sys.getenv("GITHUB_REPO")), "/issues/new")
  else ""
)
dir.create(CONFIG$feedback_dir, showWarnings = FALSE, recursive = TRUE)
FEEDBACK_CSV <- file.path(CONFIG$feedback_dir, "curator_feedback.csv")
FEEDBACK_PARQUET <- file.path(CONFIG$feedback_dir, "curator_feedback.parquet")

STATUS_COLUMNS <- c(
  "Host Species Status",
  "Body Site Status",
  "Condition Status",
  "Sequencing Type Status",
  "Taxa Level Status",
  "Sample Size Status"
)

VALID_STATES <- c("ABSENT", "PARTIALLY_PRESENT", "PRESENT")
COL_FEEDBACK_OPTIONS <- c("Not reviewed", "Correct", "Incorrect", "Unclear")
TRUE_LABEL_OPTIONS <- c("Not reviewed", "ABSENT", "PARTIALLY_PRESENT", "PRESENT")

FEEDBACK_BASE_COLS <- c(
  "PMID", "curator_id", "overall_verdict", "comment",
  "timestamp", "bioanalyzer_version"
)
PRED_PREFIX <- "pred__"
TRUE_PREFIX <- "true__"
COL_FB_PREFIX <- "col_feedback__"

safe_col <- function(col) gsub(" ", "_", col, fixed = TRUE)

#' Full feedback column schema (dynamic from STATUS_COLUMNS)
feedback_schema <- function() {
  pred_cols <- paste0(PRED_PREFIX, safe_col(STATUS_COLUMNS))
  true_cols <- paste0(TRUE_PREFIX, safe_col(STATUS_COLUMNS))
  fb_cols <- paste0(COL_FB_PREFIX, safe_col(STATUS_COLUMNS))
  c(FEEDBACK_BASE_COLS, pred_cols, true_cols, fb_cols)
}

OVERALL_VERDICT_OPTIONS <- c("Curatable", "Not curatable", "Uncertain", "Not reviewed")
