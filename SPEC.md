# Curator Desk — Specification

This specification describes the **combined system** for discovering and triaging PubMed-indexed microbiome studies suitable for BugSigDB curation. The system consists of two components:

- **BioAnalyzer** (separate CLI tool): Analyzes PubMed XML and makes LLM-powered predictions
- **curator-desk** (this repository): Displays predictions and collects curator feedback

---

## Part I: System Architecture

### 1. System Overview

**curator-desk** is a discovery and triage system for identifying **PubMed-indexed studies that are likely curatable for BugSigDB**. The system pipeline consists of:

```
PubMed XML → BioAnalyzer (CLI) → CSV predictions → curator-desk (frontend) → BugSigDB curation
```

#### Component Boundaries

**BioAnalyzer** (command-line tool, separate repository):
- Retrieves and parses PubMed XML metadata
- Uses LLM to extract structured information from abstracts
- Makes predictions on 5 key fields for BugSigDB curation
- Detects differential abundance reporting (curatability assessment)
- These predictions should be standardized to align with BugSigDB ontologies and controlled vocabularies
- Outputs CSV file with predictions and confidence status

**curator-desk** (this repository):
- Static site generator (R + Quarto) deployed to GitHub Pages
- Displays BioAnalyzer predictions in searchable, filterable table
- Collects curator feedback for ground truth validation
- Facilitates BugSigDB curation workflow

**Integration Point**: CSV file with schema:
```
PMID, Title, Journal, Year,
Host Species, Host Species Status,
Body Site, Body Site Status,
Condition, Condition Status,
Sequencing Type, Sequencing Type Status,
Sample Size, Sample Size Status
```

The system is designed to maximize curator efficiency by making relevant, standardized, and searchable candidate studies easily discoverable.

---

### 2. Goals and Non-Goals

#### 2.1 Goals

**Primary Goal**: Provide a comprehensive, automatically-updating discovery surface for identifying PubMed studies that are curatable for BugSigDB.

**Secondary Goals**:
- Validate BioAnalyzer predictions through curator feedback
- Align all structured fields with **BugSigDB ontologies and controlled vocabularies**
- Clearly indicate whether a study is **already curated in BugSigDB**
- Support curator desires such as:
  > "Parkinson's disease studies in *Mus musculus*, feces, shotgun sequencing"

#### 2.2 Non-Goals

- **Full-text storage or PDF parsing** — curators review papers separately
- **Replacement of BugSigDB's curation interface** — curator-desk is discovery/triage only
- **PubMed ingestion or ontology mapping** — handled by BioAnalyzer (separate tool)
- **Manual curation within curator-desk** — read-only interface for predictions and feedback collection only

---

## Part II: Data and Ontologies

### 3. Data Sources

#### 3.1 Input: BioAnalyzer Analysis Results

**Format**: CSV or Parquet file

**Required Columns**:
- `PMID` (integer, unique key)
- `Title` (text)
- `Journal` (text, optional)
- `Year` (integer)

**The 6 Prediction Fields**:

Each field pair consists of a **value column** (standardized term from BugSigDB ontology or controlled vocabulary) and a **status column** (extraction confidence).

**Status Values** (for all fields):
- `ABSENT`: Information not found in abstract/metadata
- `PARTIALLY_PRESENT`: Partial or ambiguous information (e.g., "humans and mice" when BugSigDB requires single host)
- `PRESENT`: Complete, unambiguous information extracted

**Target Schema** (aligned with BugSigDB standards):

| Field | Value Column | Example Value | Status Column | Standard |
|-------|--------------|---------------|---------------|----------|
| **Host Species** | `Host Species` | Homo sapiens | `Host Species Status` | NCBITaxon |
| **Body Site** | `Body Site` | feces | `Body Site Status` | UBERON |
| **Condition** | `Condition` | Parkinson disease | `Condition Status` | EFO |
| **Sequencing Type** | `Sequencing Type` | 16S | `Sequencing Type Status` | Controlled vocab |
| **Sample Size** | `Sample Size` | 98 | `Sample Size Status` | Integer |

**Example Row** (target format with standardized terms):
```csv
PMID,Title,Host Species,Host Species Status,Body Site,Body Site Status,Condition,Condition Status,Sequencing Type,Sequencing Type Status,Sample Size,Sample Size Status,has_differential_abundance,differential_abundance_confidence
32075882,Perinatal Antibiotic Exposure...,Homo sapiens,PRESENT,feces,PRESENT,antibiotic exposure,PRESENT,16S,PRESENT,98,PRESENT,TRUE,0.92
```

**Current State**: BioAnalyzer currently outputs **free text as extracted from abstracts** (e.g., "Humans", "maternal vaginal swabs and neonatal meconium"). The target is to standardize these to BugSigDB ontology terms (see Section 5 for ontology details). Current [data/sample.csv](../data/sample.csv) contains free text that curators manually standardize during BugSigDB entry.

**Curatability Assessment** (optional but recommended):
- `has_differential_abundance` (boolean): TRUE if paper reports differentially abundant taxa/features between conditions/groups
- `differential_abundance_confidence` (float 0.0-1.0): Confidence score for the differential abundance detection

**Rationale**: BugSigDB curates studies that report differential microbial abundance. This boolean allows curator-desk to filter papers by curatability without requiring an LLM. The confidence score helps prioritize papers where detection is certain.

**Future Enhancement**: BioAnalyzer may add `differential_abundance_types` (list) to distinguish between different analysis types: `taxa`, `viruses`, `metabolic_pathways`, `alpha_diversity`, `metabolomics`, `metatranscriptomics`. Papers can report multiple types. This would enable specialized filtering in curator-desk (e.g., "show only metabolomics studies").

**Computed Columns** (generated by curator-desk at build time):
- `Priority Score` (0-6 scale): PRESENT = 1.0, PARTIALLY_PRESENT = 0.5, summed across 5 fields
- `PubMed Link`: `https://pubmed.ncbi.nlm.nih.gov/{PMID}/`

#### 3.2 Reference: BugSigDB Export (Planned Feature)

**Source**: https://github.com/waldronlab/BugSigDBExports/blob/devel/full_dump.csv

**Purpose**: Join against curator-desk records by PMID to add `in_bugsigdb` boolean flag.

**Derived Column**:
- `in_bugsigdb` — TRUE if PMID exists in BugSigDB export, FALSE otherwise

**Status**: Planned enhancement, not yet implemented. When implemented, will help curators:
- Filter to show only uncurated papers
- Avoid duplicate curation efforts
- Prioritize novel studies

---

### 4. Inclusion and Exclusion Criteria

#### Scope

**Inclusion and exclusion criteria are applied by BioAnalyzer** during PubMed query and analysis. curator-desk displays all papers present in the BioAnalyzer input CSV.

#### BioAnalyzer Filtering (Reference)

For details on how BioAnalyzer selects candidate papers, see BioAnalyzer documentation. Typical criteria include:

**Inclusion**:
- Original microbiome studies
- Host-microbe interaction analyses
- Taxonomic differential abundance studies
- Studies with sufficient metadata in abstract

**Exclusion**:
- Reviews and meta-analyses
- Editorials and commentaries
- Methods-only or protocol papers
- Non-microbiome studies

#### 4.3 Draft PubMed Search Strategy

**Goal**: Broad discovery search to find most studies suitable for BugSigDB analysis without excessive false positives.

**Strategy Design**: Based on analysis of BugSigDB full_dump.csv (~1,836 unique studies, 12K signatures):
- Covers all host species (mammals, fish, plants, invertebrates)
- Covers all body sites (gut, oral, skin, environmental)
- Covers all sequencing strategies (16S, WMS, ITS, amplicon)
- Focuses on studies reporting microbial community composition or differential abundance
- Uses MeSH terms for precision and consistency

**Recommended PubMed Search Query**:

```
(
  ("Microbiota"[MeSH] OR "Gastrointestinal Microbiome"[MeSH] OR
   microbiome[Title/Abstract] OR microbiota[Title/Abstract] OR
   "microbial community"[Title/Abstract] OR "microbial communities"[Title/Abstract] OR
   "bacterial community"[Title/Abstract] OR "bacterial communities"[Title/Abstract])
  AND
  ("Sequence Analysis, DNA"[MeSH] OR "High-Throughput Nucleotide Sequencing"[MeSH] OR
   "Metagenomics"[MeSH] OR metagenomics[Title/Abstract] OR metagenome[Title/Abstract] OR
   "16S rRNA"[Title/Abstract] OR "16S ribosomal RNA"[Title/Abstract] OR
   "ITS"[Title/Abstract] OR "internal transcribed spacer"[Title/Abstract] OR
   "amplicon sequencing"[Title/Abstract] OR "shotgun sequencing"[Title/Abstract] OR
   "next-generation sequencing"[Title/Abstract] OR "whole genome sequencing"[Title/Abstract])
  AND
  (abundance[Title/Abstract] OR composition[Title/Abstract] OR
   diversity[Title/Abstract] OR dysbiosis[Title/Abstract] OR
   enriched[Title/Abstract] OR depleted[Title/Abstract] OR
   "community structure"[Title/Abstract] OR profiling[Title/Abstract])
)
NOT
(review[Publication Type] OR "systematic review"[Title/Abstract] OR
 "meta-analysis"[Publication Type] OR "meta-analysis"[Title/Abstract] OR
 protocol[Title] OR editorial[Publication Type] OR
 "methods paper"[Title/Abstract])
```

**Search Components**:

1. **Microbiome Concepts** (MeSH + Keywords):
   - **MeSH Terms**:
     - `Microbiota` - MeSH for microbial communities
     - `Gastrointestinal Microbiome` - specific GI microbiome term
   - **Free Text**: microbiome, microbiota, microbial/bacterial community
   - Rationale: Captures all host-associated and environmental microbiome studies

2. **Sequencing Methods** (MeSH + Keywords):
   - **MeSH Terms**:
     - `Sequence Analysis, DNA` - broad DNA sequencing term
     - `High-Throughput Nucleotide Sequencing` - NGS methods
     - `Metagenomics` - metagenomic sequencing
   - **Free Text**: 16S (80% of BugSigDB), metagenomics (15%), ITS, amplicon, shotgun, WGS
   - Rationale: Covers all sequencing strategies found in BugSigDB

3. **Analysis/Results Indicators**:
   - Terms indicating compositional or differential abundance analysis
   - abundance, composition, diversity (most common analysis terms)
   - dysbiosis (disease-associated changes)
   - enriched/depleted (differential abundance language)
   - community structure, profiling (descriptive analyses)
   - Rationale: Studies must report actual microbial data, not just describe methods

4. **Exclusions**:
   - Reviews, meta-analyses (no original data)
   - Protocols in title (methods-only papers)
   - Editorials (commentary only)
   - Note: Retains case-control, longitudinal, experimental studies

**Search Characteristics**:

- **Host coverage**: All organisms (no host restrictions)
  - Humans (78% of BugSigDB), mice (11%), rats (3%), fish, livestock, plants
- **Body site coverage**: All anatomical sites
  - Feces (63%), oral (7%), vaginal, skin, respiratory, etc.
- **Study design coverage**: All designs
  - Case-control, longitudinal, cross-sectional, experimental
- **Sequencing coverage**: All platforms
  - 16S rRNA, WMS, ITS, amplicon variants

**Expected Performance**:

Based on BugSigDB characteristics:
- **Estimated recall**: 80-90% of curatable studies
  - Misses: Non-standard terminology, methods-only sections
- **Estimated precision**: 40-60% for curator-desk triage
  - False positives: Description studies, methods development, non-differential results
- **Acceptable tradeoff**: Optimized for recall (discovery) over precision (filtered by curator review)

**Common False Positives** (acceptable for triage):
- Methods benchmarking papers (comparing extraction protocols)
- Population surveys without case-control comparison
- Time-series describing normal variation
- Studies measuring but not emphasizing microbial differences

**Common False Negatives** (difficult to capture):
- Papers using "flora" instead of "microbiota" (older terminology)
- Studies with differential abundance only in supplementary materials
- Papers focused on host phenotype with microbiome as secondary measure
- Non-English abstracts with English title only

**Validation Approach**:

To test search effectiveness:
1. Sample 200 random PMIDs from BugSigDB
2. Run search and calculate: `recall = (PMIDs found) / 200`
3. Sample 200 papers from search results not in BugSigDB
4. Manual review: `precision = (curatable) / 200`
5. Target: recall ≥80%, precision ≥40%

**Search Refinement Options**:

*To increase recall (find more studies):*
- Remove analysis indicators (Concept 3)
- Add older terminology: `OR flora[Title/Abstract]`
- Add ITS2, 18S for fungal/eukaryotic studies

*To increase precision (reduce false positives):*
- Add: `AND ("differential abundance"[Title/Abstract] OR "differentially abundant"[Title/Abstract])`
- Add host restrictions: `AND (humans[MeSH] OR animals[MeSH])`
- Add case-control focus: `AND ("case control"[Title/Abstract] OR "cross-sectional"[Title/Abstract])`

*Date filtering (for recent updates):*
```
AND ("2020"[Date - Publication] : "2026"[Date - Publication])
```

*Specific condition targeting (for focused curation):*
```
AND ("Parkinson Disease"[MeSH] OR "Inflammatory Bowel Diseases"[MeSH] OR
     "Obesity"[MeSH] OR "COVID-19"[MeSH])
```

**Alternative Searches**:

**Ultra-Broad Search** (Maximum Recall, ~95%):
```
("Microbiota"[MeSH] OR microbiome[Title/Abstract] OR microbiota[Title/Abstract])
AND
("Sequence Analysis, DNA"[MeSH] OR metagenom*[Title/Abstract] OR "16S"[Title/Abstract])
NOT
(review[Publication Type] OR "meta-analysis"[Publication Type])
```

**High-Precision Search** (Stricter, ~60% Precision):
```
("Microbiota"[MeSH] AND
 ("High-Throughput Nucleotide Sequencing"[MeSH] OR "Metagenomics"[MeSH])
 AND "differential abundance"[Title/Abstract])
NOT
(review[Publication Type] OR protocol[Title])
```

**Integration with BioAnalyzer**:

1. **Query PubMed**: Use recommended search above
2. **Fetch XMLs**: Download complete records via E-utilities
3. **LLM Analysis**: Extract metadata (host, body site, condition, etc.)
4. **Differential Abundance Detection**: Flag papers reporting compositional differences
5. **Output**: CSV for curator-desk with predictions and confidence scores

**Implementation Notes**:

- Use NCBI E-utilities for programmatic access
- Implement rate limiting (3 requests/second with API key)
- Repeat search daily to capture new publications
- Track search performance metrics over time
- Adjust Boolean operators based on validation results
- Maintain a list of PMIDs already analyzed by BioAnalyzer to avoid re-analysis

**curator-desk Role**: Provides filtering based on `has_differential_abundance` boolean:
- **Default view**: Show only papers with `has_differential_abundance = TRUE`
- **"Show all" toggle**: Include papers without differential abundance reporting
- **Confidence filter**: Filter by `differential_abundance_confidence` threshold (e.g., ≥ 0.7)

Curators perform final validation by reviewing abstracts and marking `overall_verdict` (Curatable / Not Curatable) in feedback form. 

---

### 5. Ontology Alignment and Term Normalization

#### 5.1 BugSigDB Ontology Standards

curator-desk aligns with **BugSigDB's ontology standards** for structured curation. BioAnalyzer predictions should eventually map to these ontologies (currently outputs free text).

**Condition**: Experimental Factor Ontology (**EFO**)
- EFO imports from MONDO, DOID, HP, and other disease ontologies
- Example: "Parkinson's disease" → **EFO:0002508**
- Browser: https://www.ebi.ac.uk/ols4/ontologies/efo
- BugSigDB stores EFO IDs in the `Condition` field

**Body Site**: Uber-anatomy Ontology (**UBERON**)
- Primary ontology for anatomical locations in BugSigDB
- Example: "feces" → **UBERON:0001988**
- Example: "blood" → **UBERON:0000178**
- Browser: https://www.ebi.ac.uk/ols4/ontologies/uberon
- BugSigDB stores UBERON IDs in the `Body site` field

**Host Species**: NCBI Taxonomy (**NCBITaxon**)
- Standard taxonomy for organisms
- Example: "Homo sapiens" → **NCBITaxon:9606**
- Example: "Mus musculus" → **NCBITaxon:10090**
- Browser: https://www.ncbi.nlm.nih.gov/taxonomy
- BugSigDB stores NCBITaxon IDs in the `Host species` field

**Sequencing Type**: BugSigDB Controlled Vocabulary
- Not a full ontology; predefined list of sequencing methods
- Values: `16S`, `shotgun`, `WGS`, `metagenomics`, `RNA-seq`, `ITS`, `amplicon`, `other`
- Source: https://bugsigdb.org/Help:Admin
- BugSigDB stores as text string in the `Sequencing type` field

**Sample Size**: Free text or integer
- Number of samples or participants analyzed
- BugSigDB stores as integer when possible

**Note**: BugSigDB also captures taxonomic rank (phylum, class, order, family, genus, species, strain), but this is determined by curators during manual curation rather than automatically extracted from abstracts.

#### 5.2 Term Translation Layer (BioAnalyzer Scope)

**Current State**: BioAnalyzer outputs **free text** extracted from abstracts (e.g., "Humans", "gut", "Obesity") with a status indicator (ABSENT/PARTIALLY_PRESENT/PRESENT).

**Future Enhancement**: Map free text to ontology IDs for direct BugSigDB compatibility.

**Example Mapping Pipeline** (illustrative, for BioAnalyzer implementation):

```
Input: "Parkinson's disease patients" (from PubMed abstract)
  ↓
Step 1: Extract disease mention → "Parkinson's disease"
  ↓
Step 2: Query OLS API → https://www.ebi.ac.uk/ols4/api/search?q=Parkinson's+disease&ontology=efo
  ↓
Step 3: Parse response → EFO:0002508 (label: "Parkinson disease")
  ↓
Output: EFO:0002508 | Parkinson disease | confidence: 1.0 (exact match)
```

**Confidence Scoring** (proposed):
- **1.0**: Exact match (label or exact synonym)
- **0.9**: Close synonym or parent term
- **0.7**: Related term or broader category
- **0.5**: Fuzzy match or requires curator review
- **0.0**: No match found

**Gap Analysis**: Currently, curators manually map BioAnalyzer free text predictions to ontology IDs when entering data into BugSigDB. Future BioAnalyzer enhancement would output ontology IDs directly, streamlining curation.

---

### 6. Curator Desk Table

#### 6.1 Core Rules

- **One row per PMID** — PMID is the primary key
- **No placeholder strings** (e.g., "AVAILABLE" / "NOT AVAILABLE") — use real values or leave empty
- **Real values or NA** — empty cells are acceptable for optional fields

#### 6.2 Required Columns (Implementation Schema)

**Identification**:
- `PMID` (integer, unique)
- `Title` (text)
- `Journal` (text, optional)
- `Year` (integer, extracted from publication date)

**The 5 Prediction Fields** (text + status pairs):
1. `Host Species` + `Host Species Status`
2. `Body Site` + `Body Site Status`
3. `Condition` + `Condition Status`
4. `Sequencing Type` + `Sequencing Type Status`
5. `Sample Size` + `Sample Size Status`

**Curatability Assessment** (optional but recommended):
- `has_differential_abundance` (boolean): Reports differential microbial abundance
- `differential_abundance_confidence` (float 0.0-1.0): Detection confidence

**Computed Fields** (auto-generated by [R/data.R](../R/data.R)):
- `Priority Score`: Numeric 0-5, where PRESENT=1.0, PARTIALLY_PRESENT=0.5
- `PubMed Link`: `https://pubmed.ncbi.nlm.nih.gov/{PMID}/`

**Planned Fields** (future enhancement):
- `in_bugsigdb` (boolean): TRUE if already curated in BugSigDB
- `differential_abundance_types` (list/comma-separated): Types of analyses reported, e.g., "taxa,metabolomics" or "viruses,alpha_diversity". Possible values: taxa, viruses, metabolic_pathways, alpha_diversity, metabolomics, metatranscriptomics

#### 6.3 Column Naming Convention

**Display Names** (in UI table, Title Case with spaces):
- "Host Species Status"
- "Body Site Status"
- "Condition Status"
- "Sequencing Type Status"
- "Sample Size Status"

**Config** ([R/config.R](../R/config.R) `STATUS_COLUMNS`):
- Matches display names exactly

**Feedback Schema** (snake_case with prefixes):
- `pred__Host_Species_Status` (BioAnalyzer prediction)
- `true__Host_Species_Status` (curator ground truth)
- `col_feedback__Host_Species_Status` (was prediction correct?)

**Note**: Future implementations may add `differential_abundance_types` to the feedback schema for curator validation of differential abundance type detection.

#### 6.4 Priority Score Calculation

Defined in [R/data.R](../R/data.R):
```r
priority_score <- function(row) {
  score <- 0
  for (col in STATUS_COLUMNS) {
    val <- toupper(trimws(as.character(row[col])))
    if (val == "PRESENT") score <- score + 1
    else if (val == "PARTIALLY_PRESENT") score <- score + 0.5
  }
  score  # Returns 0-5
}
```

**Purpose**: Higher priority scores indicate more complete metadata, helping curators focus on well-characterized studies first.

**Combined Filtering Strategy**: Use `Priority Score ≥ 4` AND `has_differential_abundance = TRUE` to identify high-quality curatable candidates.

---

## Part III: Current Implementation (curator-desk)

### 7. Data Update and Deployment Pipeline

#### 7.1 Data Update Workflow

curator-desk is a **static site** that loads data at build time. It does not ingest PubMed or run analyses.

**Data Flow**:
1. **BioAnalyzer** (separate tool) runs PubMed analysis → outputs CSV
2. **Data is provided to curator-desk** via one of:
   - Manual placement in `data/` directory (e.g., `data/sample.csv`)
   - `CURATOR_DATA_PATH` environment variable (local file path)
   - `CURATOR_DATA_URL` environment variable (remote CSV/Parquet URL)
3. **Build**: Run `quarto render` → generates static HTML in `docs/`
4. **Deploy**: Push to `main` → GitHub Action publishes `docs/` to GitHub Pages

**Example** (updating with new data):
```bash
# Option 1: Place file locally
cp /path/to/new_analysis.csv data/sample.csv
quarto render

# Option 2: Use environment variable
export CURATOR_DATA_PATH="../bioanalyzer/output/predictions.csv"
quarto render

# Option 3: Use remote URL
export CURATOR_DATA_URL="https://example.com/predictions.csv"
quarto render
```

#### 7.2 GitHub Actions Deployment

**Workflow**: [.github/workflows/quarto-publish.yml](../.github/workflows/quarto-publish.yml)

**Trigger**: Push to `main` branch

**Steps**:
1. Checkout repository
2. Install R and dependencies (DT, jsonlite, dplyr) with caching
3. Install Quarto CLI
4. Set `GITHUB_REPO` environment variable (for feedback issue links)
5. Run `quarto render`
6. Upload `docs/` as artifact
7. Deploy to GitHub Pages

**Live Site**: https://waldronlab.io/curator-desk/

**CI Validation**: [.github/workflows/ci.yml](../.github/workflows/ci.yml) runs on PRs to ensure builds succeed.

---

### 8. User Interface

curator-desk provides a **searchable, filterable table** of candidate papers with curator-friendly features.

#### 8.1 Table Features

Built with **DT** (R package wrapping DataTables.js) in [index.qmd](../index.qmd):

- **Global Search**: Text search across all columns
- **Column Filters**: Dropdown filters at top of each column (filter by condition, body site, etc.)
- **Sorting**: Click column headers to sort; default sort by Priority descending
- **Multi-column Sort**: Shift+click for secondary sort
- **Pagination**: 50 / 100 / 300 / 500 / 1000 rows per page
- **State Persistence**: Browser localStorage saves current filters, sort, and page
- **Responsive**: Mobile-friendly with collapsible columns
- **Clickable PMIDs**: Direct links to PubMed abstracts

#### 8.2 Key User Flows

**Discovery Workflow**:
1. **Filter for curatable papers**: Enable `has_differential_abundance = TRUE` filter (default)
2. **Sort by Priority** (descending) to see most complete predictions first
3. **Filter by field of interest**: Condition, Body Site, Host Species, Sequencing Type
4. **Optional**: Filter by `differential_abundance_confidence ≥ 0.7` for high-confidence papers
5. Click **PMID** to open paper on PubMed in new tab
6. Review abstract to determine curatability

**Future**: Filter by `differential_abundance_types` (e.g., "show only metabolomics studies")

**Validation Workflow** (see Section 9):
1. Select PMID from table
2. Review full abstract/paper
3. Fill feedback form with ground truth labels
4. Submit via GitHub issue OR download CSV

#### 8.3 Performance Considerations

- **Data loaded at page load**: All rows in single HTML file
- **Recommended limit**: ~1000 rows for browser performance
- **Large datasets**: Use Parquet format with `arrow` R package for efficient loading

---

### 9. Curator Feedback Mechanism

This isn't a priority, but there is a preliminary implementation that would allow validating BioAnalyzer predictions and improving model performance.

#### 9.1 Purpose

- **Collect ground truth labels** from expert curators
- **Enable iterative model improvement** for BioAnalyzer
- **Identify systematic prediction errors** (e.g., misidentifying taxa levels)
- **Build training datasets** for future ML models

#### 9.2 Feedback Schema

Defined in [R/config.R](../R/config.R) and implemented in [index.qmd](../index.qmd).

**CSV Columns** (24 total):

**Base Metadata** (6 columns):
```
PMID                    # Paper being reviewed
curator_id              # Curator initials or name
overall_verdict         # Curatable | Not curatable | Uncertain | Not reviewed
comment                 # Free-text notes
timestamp               # ISO 8601 timestamp
bioanalyzer_version     # Version of BioAnalyzer that made predictions
```

**Prediction Fields** (6 columns, `pred__` prefix):
```
pred__Host_Species_Status
pred__Body_Site_Status
pred__Condition_Status
pred__Sequencing_Type_Status
pred__Taxa_Level_Status
pred__Sample_Size_Status
```
Values copied from BioAnalyzer CSV (ABSENT / PARTIALLY_PRESENT / PRESENT).

**Ground Truth Labels** (6 columns, `true__` prefix):
```
true__Host_Species_Status
true__Body_Site_Status
true__Condition_Status
true__Sequencing_Type_Status
true__Taxa_Level_Status
true__Sample_Size_Status
```
Curator sets these to: `Not reviewed` | `ABSENT` | `PARTIALLY_PRESENT` | `PRESENT`.

**Validation Feedback** (6 columns, `col_feedback__` prefix):
```
col_feedback__Host_Species_Status
col_feedback__Body_Site_Status
col_feedback__Condition_Status
col_feedback__Sequencing_Type_Status
col_feedback__Taxa_Level_Status
col_feedback__Sample_Size_Status
```
Curator marks: `Not reviewed` | `Correct` | `Incorrect` | `Unclear`.

#### 9.3 Curator Workflow

1. **Select PMID**: Use dropdown or type PMID, click "Load row"
2. **Review Paper**: Click PMID link to open PubMed abstract
3. **For Each Field**:
   - View BioAnalyzer prediction (e.g., "Host Species Status: PRESENT")
   - Set curator TRUE label (ground truth)
   - Mark whether prediction was correct
4. **Add Context**:
   - Select `overall_verdict` (Curatable / Not curatable / Uncertain)
   - Add optional `comment` (e.g., "Missing sample size in abstract")
5. **Submit**:
   - **Submit review** → Opens GitHub new-issue page with CSV pre-filled in body
   - **Download CSV only** → Downloads CSV file for manual submission

#### 9.4 GitHub Issue Integration

**Workflow**: [.github/workflows/curator-feedback-notify.yml](../.github/workflows/curator-feedback-notify.yml)

When curator clicks "Submit review":
1. New tab opens at `{GITHUB_REPO}/issues/new`
2. Issue title pre-filled: "Curator feedback submission"
3. Issue body contains CSV in code block:
   ````markdown
   Curator feedback submission. The CSV below contains the full feedback.

   ```csv
   PMID,curator_id,overall_verdict,...
   32075882,LW,Curatable,...
   ```
   ````
4. Curator clicks "Create issue" on GitHub
5. GitHub Action posts acknowledgment comment
6. Maintainers review CSV in issue and optionally process into dataset

**Future Enhancement**: Automated parsing of feedback CSVs from issues into aggregated dataset for BioAnalyzer retraining.

---

## Part IV: Future Work

### 10. Future Enhancements

These are **planned enhancements** that are not yet implemented. The current system is functional without these features.

#### 10.1 Resolved Design Decisions

**PubMed Query Strategy**
✓ **Resolution**: Part of an offline process, followed by regular updates using a GitHub Actions workflow in curator-desk.

**API vs Bulk Ingestion**
✓ **Resolution**: CSV file exchange between BioAnalyzer and curator-desk. BioAnalyzer handles PubMed interactions.

**Precision vs Recall Tradeoffs**
✓ **Resolution**: System optimized for **recall** (surface all candidates). Curators perform final filtering via `overall_verdict`.

**Default Visibility of Curated Studies**
✓ **Resolution**: Show all papers by default. Add `in_bugsigdb` flag for filtering (planned).

**Confidence Handling for Term Mapping**
⚠️ **Status**: Future BioAnalyzer enhancement. Confidence scores would help curators prioritize uncertain predictions.

#### 10.2 Planned Features

**1. Ontology ID Output (BioAnalyzer Enhancement)**
- **Current**: BioAnalyzer outputs free text (e.g., "Parkinson's disease", "gut")
- **Planned**: Output ontology IDs (e.g., EFO:0002508, UBERON:0001988)
- **Implementation**: Integrate OLS API or ontology lookup tables
- **Benefit**: Direct BugSigDB compatibility, eliminate manual mapping step

**2. Automated BugSigDB Sync**
- **Current**: `in_bugsigdb` flag is planned but not implemented
- **Planned**: Daily GitHub Action fetches `full_dump.csv`, joins by PMID
- **Storage**: Add `in_bugsigdb` column to CSV, rebuild site automatically
- **Benefit**: Curators can filter to show only uncurated papers

**3. Confidence Scores**
- **Current**: Binary status (ABSENT / PARTIALLY_PRESENT / PRESENT)
- **Planned**: Add confidence score (0.0-1.0) for each prediction
- **Display**: Color-coded badges (high=green, medium=yellow, low=red)
- **Priority Formula**: Weight by `confidence × completeness`
- **Benefit**: Curators prioritize high-confidence predictions

**4. Incremental Updates**
- **Current**: Table rebuilt fully on each deploy
- **Planned**: Track `last_reviewed` timestamp per PMID
- **UI**: "New papers" filter, "Updated since [date]" filter
- **Storage**: Git-tracked state file or database
- **Benefit**: Curators focus on new arrivals

**5. Differential Abundance Type Detection**
- **Current**: `has_differential_abundance` is a simple boolean
- **Planned**: Add `differential_abundance_types` field (list) to distinguish analysis types
- **Values**: taxa, viruses, metabolic_pathways, alpha_diversity, metabolomics, metatranscriptomics
- **Multiple Values**: Papers can report multiple types (e.g., "taxa,metabolomics")
- **Implementation**: BioAnalyzer LLM detection of specific analysis types in abstract
- **curator-desk Filtering**:
  - "Show only taxa differential abundance"
  - "Show metabolomics OR metatranscriptomics studies"
  - Combine with other filters (e.g., host species, condition)
- **Benefit**: Enables specialized curation workflows and prioritization by analysis type

**6. Curator Analytics Dashboard**
- **Planned**: Aggregate feedback statistics from issues/CSVs
- **Metrics**:
  - Prediction accuracy by field (% correct)
  - Curator agreement scores (inter-rater reliability)
  - Common failure modes
  - Differential abundance detection accuracy by type
- **Purpose**: Guide BioAnalyzer improvements, identify data quality issues
- **Display**: Separate Quarto page with plots (ggplot2 / Plotly)

---

### 11. Long-Term Vision

curator-desk becomes the **primary discovery surface** for BugSigDB curation, enabling:

- **Near-complete PubMed coverage**: Automated ingestion of all microbiome studies
- **Zero-effort curation**: BioAnalyzer predictions accurate enough for direct import to BugSigDB (human-in-the-loop validation only)
- **Community curation**: Distributed curation by multiple teams, coordinated through curator-desk
- **Real-time updates**: New papers appear in curator-desk within 24 hours of PubMed indexing

This vision requires:
- High-accuracy ontology mapping (90%+ precision)
- Confidence-weighted prioritization
- Robust feedback loop for model improvement
- Integration with BugSigDB's curation API

---

## Part V: Technical Reference

### 12. Technical Implementation

Detailed implementation guide for developers extending or deploying curator-desk.

#### 12.1 Repository Structure

```
curator-desk/
├── data/                   # Input CSV files
│   └── sample.csv          # Example BioAnalyzer output (31 papers)
├── R/                      # Data processing logic
│   ├── config.R            # STATUS_COLUMNS, schema definitions
│   ├── data.R              # load_data(), normalize_dataset(), priority_score()
│   └── feedback.R          # Feedback schema helpers (reference)
├── index.qmd               # Main Quarto page (table + feedback form)
├── _quarto.yml             # Quarto project config (output-dir: docs)
├── styles.css              # Custom CSS (full-width layout)
├── docs/                   # Generated static site (git-tracked for Pages)
│   ├── index.html          # Rendered output
│   └── search.json         # Quarto search index
├── curator-feedback/       # Directory for feedback CSVs (currently unused)
├── .github/workflows/      # CI/CD pipelines
│   ├── ci.yml              # Build validation on PRs
│   ├── quarto-publish.yml  # Deploy to GitHub Pages
│   └── curator-feedback-notify.yml  # Acknowledge feedback issues
└── README.md               # User guide (build, deploy, configuration)
```

#### 12.2 Key Dependencies

**R Packages**:
- `DT` — Interactive DataTables
- `jsonlite` — JSON export for JavaScript form
- `dplyr` — Data manipulation
- `arrow` (optional) — Parquet support for large datasets

**Installation**:
```bash
Rscript -e 'install.packages(c("DT", "jsonlite", "dplyr", "arrow"), repos="https://cloud.r-project.org")'
```

**Quarto**:
- Version ≥ 1.3 recommended
- Download: https://quarto.org/docs/get-started/

#### 12.3 Configuration Options

Set via environment variables before `quarto render`:

**Data Source**:
```bash
# Option 1: Local file path
export CURATOR_DATA_PATH="data/analyzed_papers.csv"

# Option 2: Remote URL (raw GitHub, S3, etc.)
export CURATOR_DATA_URL="https://raw.githubusercontent.com/user/repo/main/data.csv"

# Default (if neither set): data/sample.csv
```

**Build-Time Config**:
```bash
# GitHub repo URL for feedback issue links
export GITHUB_REPO="https://github.com/waldronlab/curator-desk"

# BioAnalyzer version (fixed in feedback form)
export BIOANALYZER_VERSION="1.2.0"

# Curator ID default (pre-fills form)
export USER="curator_initials"
```

#### 12.4 Development Workflow

**Local Development**:
```bash
# Live preview with hot reload
quarto preview
# Opens http://localhost:4321

# Test with different data
export CURATOR_DATA_PATH="test_data.csv"
quarto preview
```

**Production Build**:
```bash
quarto render
# Output written to docs/

# Check output
open docs/index.html
```

**Deployment**:
```bash
# Commit rendered output (required for GitHub Pages)
git add docs/
git commit -m "Update with new BioAnalyzer results"
git push origin main
# GitHub Action automatically deploys to Pages
```

#### 12.5 Adding New Status Fields

To add a new prediction field (e.g., "Study Design Status"):

1. **Update Config** ([R/config.R](../R/config.R)):
   ```r
   STATUS_COLUMNS <- c(
     "Host Species Status",
     "Body Site Status",
     "Condition Status",
     "Sequencing Type Status",
     "Sample Size Status",
     "Study Design Status"  # <-- Add here
   )
   ```

2. **Update Input CSV**: Ensure BioAnalyzer outputs columns:
   - `Study Design` (text)
   - `Study Design Status` (ABSENT / PARTIALLY_PRESENT / PRESENT)

3. **Update Feedback Form** ([index.qmd](../index.qmd) line ~355):
   ```javascript
   const statusCols = [
     "Host Species Status",
     // ...
     "Study Design Status"  // <-- Add here
   ];
   ```

4. **Rebuild**:
   ```bash
   quarto render
   ```

The table, priority score, and feedback form will automatically include the new field.

#### 12.6 Troubleshooting

**Problem**: `docs/index.html` is empty or has no data
**Solution**: Check `CURATOR_DATA_PATH` / `CURATOR_DATA_URL`. Verify CSV has `PMID` column and valid data.

**Problem**: Table shows "No data loaded"
**Solution**: Ensure CSV is in `data/` or set environment variable correctly.

**Problem**: Feedback "Submit review" button doesn't open GitHub
**Solution**: Set `GITHUB_REPO` environment variable before rendering.

**Problem**: GitHub Pages shows 404
**Solution**: Enable Pages in repository settings (Settings → Pages → Source: Deploy from a branch → Branch: main, Folder: /docs).

---

### 13. Integration with BugSigDB

curator-desk bridges discovery/triage and BugSigDB's structured curation.

#### 13.1 Current Workflow

```
1. Curator uses curator-desk to identify promising candidates
   └─> Sort by Priority, filter by condition/body site
2. Curator clicks PMID → opens PubMed abstract
3. Curator reads full text (PDF/HTML)
4. Curator logs into BugSigDB (MediaWiki)
5. Curator creates new signature entry with structured fields
   └─> Manually maps free text to ontology IDs
6. Curator submits feedback in curator-desk (optional)
```

**Pain Points**:
- Manual ontology mapping (free text → EFO / UBERON IDs)
- No pre-filled data transfer from curator-desk to BugSigDB
- Duplicate effort entering PMID, title, journal

#### 13.2 Efficiency Opportunities

**Near-term**:
- **Export curatable PMIDs**: Download list of PMIDs marked "Curatable" in feedback
- **Direct BugSigDB links**: Add button "Curate this paper in BugSigDB" with PMID pre-filled in URL

**Long-term** (requires BugSigDB API):
- **Pre-fill BugSigDB form**: Send BioAnalyzer predictions to BugSigDB new-entry form
- **Auto-import high-confidence**: For predictions with confidence > 0.95, create draft BugSigDB entries for curator review
- **Bidirectional sync**: BugSigDB updates reflected in curator-desk `in_bugsigdb` flag within 24 hours

#### 13.3 Data Flow Diagram

```
┌─────────────┐
│  PubMed XML │
└──────┬──────┘
       │
       ▼
┌────────────────────────────────┐
│ BioAnalyzer (CLI)              │
│ - Parse metadata               │
│ - LLM extraction               │
│ - Predict 5 fields             │
│ - Detect differential abundance│
└──────┬─────────────────────────┘
       │ predictions.csv
       ▼
┌─────────────────────┐
│ curator-desk        │
│ - Display table     │
│ - Filter curatable  │
│ - Collect feedback  │
└──────┬──────────────┘
       │ Curator review
       ▼
┌─────────────────────┐
│ Selected PMIDs +    │
│ Ground truth labels │
└──────┬──────────────┘
       │
       ├─> BugSigDB curation interface (manual entry)
       │
       └─> Feedback loop (improve BioAnalyzer)

┌─────────────────────┐
│ BugSigDB full_dump  │
│ (already curated)   │
└──────┬──────────────┘
       │
       └─> (Planned) Join with curator-desk → in_bugsigdb flag
```

---

## Appendices

### Appendix A: Sample CSV Schema

**Minimal Required Schema**:
```csv
PMID,Title,Host Species,Host Species Status,Body Site,Body Site Status,Condition,Condition Status,Sequencing Type,Sequencing Type Status,Sample Size,Sample Size Status
```

**Recommended Additional Columns**:
```csv
has_differential_abundance,differential_abundance_confidence
```

**Current State Example Row** (PMID 32075882 from [data/sample.csv](../data/sample.csv) - free text):
```csv
32075882,"Perinatal Antibiotic Exposure...","Humans","PRESENT","maternal vaginal swabs and neonatal meconium","PRESENT","The impact of perinatal antibiotic prophylaxis...","PRESENT","sequencing the 16S rRNA gene","PRESENT","Ninety-eight pregnant women and their neonates","PRESENT"
```

**Target Format Example Row** (with standardized terms and curatability):
```csv
32075882,"Perinatal Antibiotic Exposure...","Homo sapiens","PRESENT","feces","PRESENT","antibiotic exposure","PRESENT","16S","PRESENT","98","PRESENT","TRUE","0.92"
```

**Optional Columns**:
- `Journal` (text)
- `Year` (integer)
- `Summary` (text, LLM-generated)
- `Publication Date` (date, for Year extraction)
- `Processing Time` (numeric, BioAnalyzer runtime)
- `differential_abundance_types` (list, future): e.g., "taxa,metabolomics"

---

### Appendix B: BugSigDB Ontology Quick Reference

Quick reference for ontologies used in BugSigDB curation.

| Field | Ontology | Example Term | Example ID | Browser |
|-------|----------|--------------|-----------|---------|
| **Condition** | EFO | Parkinson disease | EFO:0002508 | https://www.ebi.ac.uk/ols4/ontologies/efo |
| | | Obesity | EFO:0001073 | |
| | | Type 2 diabetes mellitus | EFO:0001360 | |
| **Body Site** | UBERON | feces | UBERON:0001988 | https://www.ebi.ac.uk/ols4/ontologies/uberon |
| | | blood | UBERON:0000178 | |
| | | saliva | UBERON:0001836 | |
| | | colon | UBERON:0001155 | |
| **Host Species** | NCBITaxon | Homo sapiens | NCBITaxon:9606 | https://www.ncbi.nlm.nih.gov/taxonomy |
| | | Mus musculus | NCBITaxon:10090 | |
| | | Rattus norvegicus | NCBITaxon:10116 | |
| **Sequencing Type** | Controlled Vocab | 16S | (text) | https://bugsigdb.org/Help:Admin |
| | | shotgun | (text) | |
| | | WGS | (text) | |

**Lookup Tools**:
- EFO/UBERON: https://www.ebi.ac.uk/ols4/ (Ontology Lookup Service)
- NCBITaxon: https://www.ncbi.nlm.nih.gov/taxonomy
- BugSigDB Admin Help: https://bugsigdb.org/Help:Admin

---

### Appendix C: Glossary

**BioAnalyzer**: Command-line tool that analyzes PubMed XML and makes LLM-powered predictions about microbiome study metadata.

**BugSigDB**: Manually curated database of microbiome study signatures. URL: https://bugsigdb.org

**curator-desk**: This repository. Static site for discovering and triaging BugSigDB-curatable papers.

**DT (DataTables)**: R package for interactive HTML tables. Wraps DataTables.js.

**EFO (Experimental Factor Ontology)**: Ontology for experimental variables, diseases, and phenotypes. Imports from MONDO, DOID, HP. Used by BugSigDB for conditions.

**MeSH (Medical Subject Headings)**: Controlled vocabulary for indexing biomedical literature in PubMed.

**OLS (Ontology Lookup Service)**: Web service for browsing and searching biomedical ontologies. URL: https://www.ebi.ac.uk/ols4/

**PMID (PubMed Identifier)**: Unique integer ID for articles in PubMed database.

**Quarto**: Open-source scientific publishing system. Renders `.qmd` markdown files to HTML, PDF, etc.

**Status Values**:
- **ABSENT**: Information not found in abstract/metadata
- **PARTIALLY_PRESENT**: Partial or ambiguous information
- **PRESENT**: Complete, unambiguous information

**UBERON (Uber-anatomy Ontology)**: Cross-species anatomy ontology. Used by BugSigDB for body sites.

**Priority Score**: Computed metric (0-6 scale) indicating completeness of metadata. Higher = more likely curatable.

---

## Document Change History

- **2024-04-02**: Major restructure to clarify BioAnalyzer vs curator-desk scope, fix ontology errors (EFO not MONDO/DOID), add missing sections (Curator Feedback, Technical Implementation, BugSigDB Integration), resolve open design decisions, add appendices. [Previous version](SPEC.md.backup)
