# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**curator-desk** is a static Quarto site (R + DT DataTables) deployed to GitHub Pages. It displays BioAnalyzer CSV predictions for PubMed microbiome studies and collects curator feedback via GitHub issues. There is no server — all data is embedded at build time.

The pipeline: `PubMed XML → BioAnalyzer (separate CLI) → CSV → curator-desk (this repo) → BugSigDB curation`.

## Commands

```bash
# Install R dependencies (managed by renv)
Rscript -e 'renv::restore()'

# Run unit tests
Rscript tests/testthat.R

# Build the site (output goes to docs/)
quarto render

# Live preview with hot reload (http://localhost:4321)
quarto preview

# Build with a custom data source
CURATOR_DATA_PATH="path/to/predictions.csv" quarto render
CURATOR_DATA_URL="https://raw.githubusercontent.com/.../data.csv" quarto render
```

CI runs `Rscript tests/testthat.R` before `quarto render` on every PR and push to main.

## Architecture

### R source files (loaded by `index.qmd` at render time)

- **`R/config.R`** — single source of truth for the schema. `STATUS_COLUMNS` drives the priority score, feedback column names, and the JS form. `CONFIG` reads env vars (`GITHUB_REPO`, `BIOANALYZER_VERSION`, `USER`). `feedback_schema()` generates all 24 feedback CSV column names dynamically.
- **`R/data.R`** — `load_data(path)` (CSV or Parquet, with SSRF guard for URLs), `normalize_dataset(df)` (coerces PMID, normalises status strings, computes `Priority`, adds `PubMed Link`), `assert_public_host(url)` (blocks private IP ranges).
- **`R/feedback.R`** — `load_feedback`, `save_feedback`, `upsert_feedback`, `feedback_row` helpers for the feedback CSV schema. Used for reference/Shiny use; the static site builds the CSV entirely in JS.

### `index.qmd`

The only page. R chunks source the three files above, load and normalize the dataset, then render a DT table and serialize `tableData` + `CONFIG` as JSON into hidden `<script>` tags for the JS form.

### `js/feedback-form.js`

Reads `#curator-table-data` and `#curator-config` JSON blobs. Populates the feedback form when a PMID is selected. Builds the 24-column CSV in-browser and either opens a GitHub new-issue URL with it pre-filled in the body, or triggers a download.

### Key schema invariant

`STATUS_COLUMNS` in `R/config.R` and `statusCols` in `js/feedback-form.js` must stay in sync. Adding a new prediction field requires updating both, plus ensuring BioAnalyzer outputs the matching `{Field} Status` column in the CSV.

## Data source

Data is resolved at render time in this order:
1. `CURATOR_DATA_URL` env var (remote CSV/Parquet — blocked if private host)
2. `CURATOR_DATA_PATH` env var (local file)
3. Default: `data/sample.csv`

## Testing

Tests live in `tests/testthat/` and cover `R/config.R` (`test-config.R`) and `R/data.R` (`test-data.R`). This is not an R package, so there is no `DESCRIPTION` — the runner is `tests/testthat.R` (standalone script). Run a specific test file by sourcing it after sourcing `R/config.R` and `R/data.R`.

## Deployment

- `docs/` is git-tracked and served by GitHub Pages from the `main` branch.
- `.github/workflows/quarto-publish.yml` builds and deploys on push to `main`.
- `.github/workflows/ci.yml` validates PRs (tests + render, but does not deploy).
- `.github/workflows/curator-feedback-notify.yml` posts an acknowledgment comment when a "Curator feedback" issue is opened.
