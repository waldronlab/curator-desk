# Schema and options (aligned with curator_table/app.py)
# Used for normalization, feedback column names, and UI options.
# Config: env overrides (same as Python CONFIG)
CONFIG <- list(
  feedback_dir = Sys.getenv("FEEDBACK_DIR", "results"),
  curator_id_default = Sys.getenv("USER", ""),
  bioanalyzer_version_default = Sys.getenv("BIOANALYZER_VERSION", "1.0.0"),
  # Base URL for new issue; Submit review opens this with title and body pre-filled
  feedback_issue_url = if (nzchar(trimws(Sys.getenv("GITHUB_REPO", ""))))
    paste0(trimws(Sys.getenv("GITHUB_REPO")), "/issues/new")
  else ""
)
dir.create(CONFIG$feedback_dir, showWarnings = FALSE, recursive = TRUE)
FEEDBACK_CSV <- file.path(CONFIG$feedback_dir, "curator_feedback.csv")
FEEDBACK_PARQUET <- file.path(CONFIG$feedback_dir, "curator_feedback.parquet")

# Simplified curator-desk schema (per Levi Waldron review): plain value per
# field, plus an ontology ID for the 3 fields that map to an external
# ontology. No PRESENT/PARTIALLY_PRESENT/ABSENT Status, Mapping Confidence,
# or Priority columns - see docs/CURATOR_DESK_CSV_FORMAT.md in the parent repo.
VALUE_COLUMNS <- c(
  "Host Species",
  "Body Site",
  "Condition",
  "Sample Size",
  "Sequencing Type"
)

ONTOLOGY_ID_COLUMNS <- c(
  "Host Species Ontology ID",
  "Body Site Ontology ID",
  "Condition Ontology ID"
)

# Picker metadata (not shown as a table column) - "label|ontology_id;
# label|ontology_id", populated only when a field's mapping tier isn't auto.
ONTOLOGY_CANDIDATES_COLUMNS <- c(
  "Host Species Ontology Candidates",
  "Body Site Ontology Candidates",
  "Condition Ontology Candidates"
)

BOOLEAN_COLUMNS <- c(
  "Differential Abundance",
  "In bsgdb"
)

COL_FEEDBACK_OPTIONS <- c("Not reviewed", "Correct", "Incorrect", "Unclear")

FEEDBACK_BASE_COLS <- c(
  "PMID", "curator_id", "overall_verdict", "comment",
  "timestamp", "bioanalyzer_version"
)
PRED_PREFIX <- "pred__"
TRUE_PREFIX <- "true__"
COL_FB_PREFIX <- "col_feedback__"

safe_col <- function(col) gsub(" ", "_", col, fixed = TRUE)

#' Full feedback column schema (dynamic from VALUE_COLUMNS + ONTOLOGY_ID_COLUMNS).
#'
#' Every value field gets a pred/true/col_feedback triplet (curator confirms
#' or corrects the extracted text); the 3 ontology-mapped fields additionally
#' get a pred/true Ontology ID pair (curator confirms/picks the ontology
#' mapping - see ONTOLOGY_CANDIDATES_COLUMNS and js/feedback-form.js).
feedback_schema <- function() {
  pred_cols <- paste0(PRED_PREFIX, safe_col(VALUE_COLUMNS))
  true_cols <- paste0(TRUE_PREFIX, safe_col(VALUE_COLUMNS))
  fb_cols <- paste0(COL_FB_PREFIX, safe_col(VALUE_COLUMNS))
  pred_onto_cols <- paste0(PRED_PREFIX, safe_col(ONTOLOGY_ID_COLUMNS))
  true_onto_cols <- paste0(TRUE_PREFIX, safe_col(ONTOLOGY_ID_COLUMNS))
  c(FEEDBACK_BASE_COLS, pred_cols, true_cols, fb_cols, pred_onto_cols, true_onto_cols)
}

OVERALL_VERDICT_OPTIONS <- c("Curatable", "Not curatable", "Uncertain", "Not reviewed")
