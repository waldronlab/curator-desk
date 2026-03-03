# Curator Desk

**Curator dashboard for reviewing BioAnalyzer predictions** — sortable table, field-level feedback, submit via GitHub Issues & PRs. Built with R, Quarto, and DT; runs on **GitHub Pages** so curators can use it from the browser (no server or Docker).

## Features (aligned with Streamlit app)

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

## Deploy to GitHub Pages

1. **Build** the site (see above). The project is set up to write output to `docs/`.

2. **Publish `docs/`:**
   - **Option A — Branch `main` / folder `docs`:**  
     Push the repo. In GitHub: **Settings → Pages → Source**: “Deploy from a branch”. Branch: `main`, folder: `/docs`. Save. The site will be at `https://<org>.github.io/<repo>/`.
   - **Option B — Branch `gh-pages`:**  
     Set `output-dir` in `_quarto.yml` to a different directory (e.g. `_site`) and use a GitHub Action to build and push to the `gh-pages` branch; then set Pages to deploy from `gh-pages`.

3. Add a **`.nojekyll`** file in the root of the deployed content (e.g. in `docs/`) so GitHub Pages doesn’t treat it as Jekyll:

   ```bash
   touch docs/.nojekyll
   ```

   Commit and push so `docs/.nojekyll` is in the repo.

## Feedback workflow (GitHub Pages)

1. **Curators** open the table, pick a PMID, fill the feedback form, and click **Submit review** (no file download).
2. A new browser tab opens on your repo’s **new-issue** page with the feedback **pre-filled** in the body (CSV in a code block). The curator clicks **Submit** once on GitHub to create the issue.
3. A **GitHub Action** (`.github/workflows/curator-feedback-notify.yml`) runs when an issue titled "Curator feedback submission" is opened:
   - Extracts the CSV from the issue body.
   - Saves it to **`curator-feedback/`** on a new branch.
   - Opens a **Pull Request** with that file so the maintainer can view and **download** the CSV (with curator initials, comments, and field-by-field validation).
   - Comments on the issue with the PR link and notifies **ronald2ouma2@gmail.com** (if SMTP secrets are set).

**Build-time options:**

- Set **`GITHUB_REPO`** (e.g. `https://github.com/owner/repo`) so Submit review opens your repo’s new-issue page with the feedback in the body.
- Set **`BIOANALYZER_VERSION`** (default `1.0.0`) so the version field is fixed for all curators.

**Email notification:** Add repository secrets `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM` to send the maintainer an email when a PR is created. Without them, the Action still creates the PR and comments on the issue.

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
