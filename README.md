# Curator Desk

**Curator dashboard for reviewing BioAnalyzer predictions** — sortable table, field-level feedback, submit via GitHub Issues & PRs. Built with R, Quarto, and DT; runs on **GitHub Pages** so curators can use it from the browser (no server or Docker).

**Live site:** [https://waldronlab.io/curator-desk/](https://waldronlab.io/curator-desk/)

## Features (aligned with Streamlit app in BioAnalyzer-Backend)

- **Data:** Load CSV (or Parquet if `arrow` is installed) from a path or URL at build time.
- **Table:** Sortable, searchable, filterable (DT DataTables); Priority Score; PubMed links.
- **Feedback:** Form for curator ID, PMID, overall verdict, comment, BioAnalyzer version, and field-by-field validation (curator TRUE label + “Was BioAnalyzer correct?”). Feedback is **downloaded as CSV** (one row per submission) for you to collect via email, GitHub Issues, or your own backend.

## Prerequisites

- [R](https://www.r-project.org/) (≥ 4.0)
- [Quarto](https://quarto.org/docs/get-started/) CLI
- R packages: `DT`, `jsonlite` (and `arrow` if you use Parquet)

```bash
Rscript -e 'install.packages(c("DT", "jsonlite", "arrow"), repos = "https://cloud.r-project.org")'
```

## Build locally

From the **repo root** (e.g. `curator-desk/`):

```bash
quarto render
```

Output is written to `docs/`. Open `docs/index.html` in a browser to test.

## Data source

The table is built from a single dataset at **render time**:

- **Default:** `data/sample.csv` (minimal example).
- **Custom:** Set one of:
  - `CURATOR_DATA_PATH` — path to a local CSV/Parquet (e.g. `../results/analysis_results.csv`).
  - `CURATOR_DATA_URL` — URL to a CSV/Parquet (e.g. raw GitHub URL).

Examples:

```bash
# Use a local file
export CURATOR_DATA_PATH="data/sample.csv"
quarto render

# Use a URL (e.g. raw file from GitHub)
export CURATOR_DATA_URL="https://raw.githubusercontent.com/your-org/your-repo/main/data/predictions.csv"
quarto render
```

To update the table with new data, re-run `quarto render` (or use a CI job that does this and publishes `docs/`).

## CI and deployment

- **CI (`.github/workflows/ci.yml`)** runs on every **pull request** and **push** to `main`: builds the site with Quarto, installs R dependencies (with cache), and checks that `docs/index.html` is produced. Use it as a **required status check** so PRs must pass before merge: **Settings → Branches → Branch protection rules** for `main` → Require status checks → select **"Build & validate"**.
- **Deploy (`.github/workflows/quarto-publish.yml`)** runs on **push to `main`** only: builds the site, uploads the artifact, and deploys to GitHub Pages. R package caching is enabled to speed up runs.

## Feedback workflow (GitHub Pages only)

This project uses **only GitHub Pages**; no other platform (e.g. Vercel) is required.

1. **Curators** fill the feedback form and click **Submit review**.
2. A new tab opens on your repo’s **new-issue** page with the title and body **pre-filled** (the feedback CSV is in the body). The curator clicks **Create** on GitHub to create the issue.
3. **Maintainers review in the issue** — the full feedback (curator initials, comments, field-by-field validation) is in the issue body as a CSV block.

Optionally, the **GitHub Action** (`.github/workflows/curator-feedback-notify.yml`) runs when an issue titled "Curator feedback submission" is opened: it extracts the CSV, saves it under **`curator-feedback/`** on a new branch, opens a **Pull Request** with that file, and comments on the issue with the PR link. Review can be done directly in the issue or via the PR.

**Build-time options:**

- **`GITHUB_REPO`** — repo URL (e.g. `https://github.com/owner/repo`) so Submit review opens the correct new-issue page. Set in your deploy workflow or locally before `quarto render`.
- **`BIOANALYZER_VERSION`** (default `1.0.0`) — fixed version in the form.

## File layout

```
curator-desk/
  _quarto.yml     # Quarto project, output-dir: docs
  index.qmd       # Main page: table + feedback form
  R/
    config.R      # STATUS_COLUMNS, options, feedback schema
    data.R        # load_data(), normalize_dataset(), priority_score, PMID link
    feedback.R    # feedback row builder (for reference; CSV is built in JS)
  data/           # Put your analyzed-papers CSV here
  curator-feedback/   # Feedback CSVs from submitted reviews (via GitHub Action)
  docs/           # Rendered output (git-tracked for Pages)
  README.md       # This file
```

## Schema alignment

Column names and options match `curator_table/app.py`:

- Status values: `ABSENT`, `PARTIALLY_PRESENT`, `PRESENT`
- Feedback columns: `PMID`, `curator_id`, `overall_verdict`, `comment`, `timestamp`, `bioanalyzer_version`, plus `pred__*`, `true__*`, `col_feedback__*` for each status field.

CSVs downloaded from this app can be combined with feedback from the Streamlit app for analysis.
