# Schema and options (aligned with Curator Desk specification §6.2)
# Five prediction fields + status pairs; Priority Score computed in data.R.

CONFIG <- list(
  feedback_dir = Sys.getenv("FEEDBACK_DIR", "results"),
  curator_id_default = Sys.getenv("USER", ""),
  bioanalyzer_version_default = Sys.getenv("BIOANALYZER_VERSION", "1.0.0"),
  feedback_issue_url = if (nzchar(trimws(Sys.getenv("GITHUB_REPO", ""))))
    paste0(trimws(Sys.getenv("GITHUB_REPO")), "/issues/new")
  else "",
  # Triage defaults (spec §8.2): show curatable candidates first
  triage_da_only = tolower(Sys.getenv("CURATOR_TRIAGE_DA_ONLY", "true")) %in% c("1", "true", "yes"),
  min_da_confidence = suppressWarnings(
    as.numeric(Sys.getenv("CURATOR_MIN_DA_CONFIDENCE", "0"))
  ),
  hide_in_bugsigdb = tolower(Sys.getenv("CURATOR_HIDE_IN_BUGSIGDB", "false")) %in% c("1", "true", "yes")
)
if (is.na(CONFIG$min_da_confidence)) CONFIG$min_da_confidence <- 0

dir.create(CONFIG$feedback_dir, showWarnings = FALSE, recursive = TRUE)
FEEDBACK_CSV <- file.path(CONFIG$feedback_dir, "curator_feedback.csv")
FEEDBACK_PARQUET <- file.path(CONFIG$feedback_dir, "curator_feedback.parquet")

BUGSIGDB_DUMP_URL <- "https://raw.githubusercontent.com/waldronlab/BugSigDBExports/devel/full_dump.csv"

# Five prediction fields per spec §6.2 (taxonomic rank is curator-determined in BugSigDB)
STATUS_COLUMNS <- c(
  "Host Species Status",
  "Body Site Status",
  "Condition Status",
  "Sequencing Type Status",
  "Sample Size Status"
)

VALUE_COLUMNS <- c(
  "Host Species",
  "Body Site",
  "Condition",
  "Sequencing Type",
  "Sample Size"
)

# Optional mapping-confidence columns exported by BioAnalyzer curator_desk_csv
MAPPING_CONFIDENCE_COLUMNS <- c(
  "Host Species Mapping Confidence",
  "Body Site Mapping Confidence",
  "Condition Mapping Confidence"
)

BOOLEAN_COLUMNS <- c(
  "has_differential_abundance",
  "in_bugsigdb"
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

#' Full feedback column schema (dynamic from STATUS_COLUMNS; 5 fields × 3 prefixes)
feedback_schema <- function() {
  pred_cols <- paste0(PRED_PREFIX, safe_col(STATUS_COLUMNS))
  true_cols <- paste0(TRUE_PREFIX, safe_col(STATUS_COLUMNS))
  fb_cols <- paste0(COL_FB_PREFIX, safe_col(STATUS_COLUMNS))
  c(FEEDBACK_BASE_COLS, pred_cols, true_cols, fb_cols)
}

OVERALL_VERDICT_OPTIONS <- c("Curatable", "Not curatable", "Uncertain", "Not reviewed")
