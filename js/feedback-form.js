(function() {
  const safeCol = c => c.replace(/ /g, "_");
  const ONTO_OTHER = "__other__";

  // Fallback only: the real lists come from R/config.R's VALUE_COLUMNS /
  // ONTOLOGY_ID_COLUMNS via the "curator-config" JSON script tag below, so
  // adding/removing a field there is enough - this file no longer needs its
  // own copy. These arrays only matter if that script tag is ever missing
  // (e.g. a stale cached page).
  const DEFAULT_VALUE_COLS = [
    "Host Species", "Body Site", "Condition", "Sample Size", "Sequencing Type"
  ];
  const DEFAULT_ONTOLOGY_ID_COLS = [
    "Host Species Ontology ID", "Body Site Ontology ID", "Condition Ontology ID"
  ];

  let tableData = [];
  const el = document.getElementById("curator-table-data");
  if (el) try { tableData = JSON.parse(el.textContent); } catch (_) {}

  const configEl = document.getElementById("curator-config");
  let feedbackIssueUrl = "";
  let valueCols = DEFAULT_VALUE_COLS;
  let ontologyIdCols = DEFAULT_ONTOLOGY_ID_COLS;
  if (configEl) {
    try {
      const cfg = JSON.parse(configEl.textContent);
      if (cfg.curator_id_default) document.getElementById("curator_id").value = cfg.curator_id_default;
      const verEl = document.getElementById("bioanalyzer_version");
      if (verEl) verEl.value = cfg.bioanalyzer_version_default || "1.0.0";
      if (cfg.feedback_issue_url) feedbackIssueUrl = cfg.feedback_issue_url;
      if (Array.isArray(cfg.value_columns) && cfg.value_columns.length) valueCols = cfg.value_columns;
      if (Array.isArray(cfg.ontology_id_columns) && cfg.ontology_id_columns.length) ontologyIdCols = cfg.ontology_id_columns;
    } catch (_) {}
  }

  function ontologyIdColFor(valueCol) {
    const candidate = valueCol + " Ontology ID";
    return ontologyIdCols.indexOf(candidate) !== -1 ? candidate : null;
  }
  function ontologyCandidatesColFor(valueCol) {
    return valueCol + " Ontology Candidates";
  }

  const schema = ["PMID", "curator_id", "overall_verdict", "comment", "timestamp", "bioanalyzer_version"]
    .concat(valueCols.map(c => "pred__" + safeCol(c)))
    .concat(valueCols.map(c => "true__" + safeCol(c)))
    .concat(valueCols.map(c => "col_feedback__" + safeCol(c)))
    .concat(ontologyIdCols.map(c => "pred__" + safeCol(c)))
    .concat(ontologyIdCols.map(c => "true__" + safeCol(c)));
  if (!feedbackIssueUrl && typeof window !== "undefined") {
    if (window.location.hostname.endsWith(".github.io")) {
      var path = window.location.pathname.replace(/\/index\.html$/i, "").replace(/^\//, "").split("/").filter(Boolean);
      var repo = path[0];
      if (repo) {
        var user = window.location.hostname.replace(".github.io", "");
        feedbackIssueUrl = "https://github.com/" + user + "/" + repo + "/issues/new";
      }
    } else if (window.location.hostname === "waldronlab.io" && window.location.pathname.indexOf("curator-desk") !== -1) {
      feedbackIssueUrl = "https://github.com/waldronlab/curator-desk/issues/new";
    }
  }

  function setTitleFromPmid(pmid) {
    const row = tableData.find(r => String(r.PMID) === String(pmid));
    const titleEl = document.getElementById("title-prefill");
    if (row) {
      titleEl.textContent = row.Title || "(no title)";
      updatePredictionsForRow(row);
      const section = document.getElementById("field-validation-section");
      if (section) section.scrollIntoView({ behavior: "smooth", block: "start" });
    } else {
      titleEl.textContent = "(PMID not in table)";
      clearPredictions();
    }
  }

  function getPredictionValue(row, col) {
    if (!row) return "";
    const withSpaces = row[col];
    if (withSpaces !== undefined && withSpaces !== null && String(withSpaces).trim() !== "") return String(withSpaces).trim();
    const withUnderscores = row[col.replace(/\s+/g, "_")];
    if (withUnderscores !== undefined && withUnderscores !== null && String(withUnderscores).trim() !== "") return String(withUnderscores).trim();
    return "";
  }

  // Parse the compact "label|ontology_id; label|ontology_id" candidates
  // string (see scripts/cli_rendering.py::_field_ontology_candidates).
  function parseCandidates(raw) {
    if (!raw) return [];
    return raw.split(";").map(s => s.trim()).filter(Boolean).map(pair => {
      const idx = pair.indexOf("|");
      return idx === -1 ? { label: pair, id: "" } : { label: pair.slice(0, idx), id: pair.slice(idx + 1) };
    }).filter(c => c.id);
  }

  const predictionPlaceholder = "Select a PMID above and click Load row to see BioAnalyzer's prediction.";

  function populateOntologySelect(valueCol, row) {
    const ontoCol = ontologyIdColFor(valueCol);
    if (!ontoCol) return;
    const s = safeCol(ontoCol);
    const predEl = document.getElementById("pred_" + s);
    const selectEl = document.getElementById("true_" + s);
    const manualEl = document.getElementById("true_" + s + "_manual");
    if (!selectEl) return;
    const predictedId = getPredictionValue(row, ontoCol);
    if (predEl) predEl.textContent = predictedId ? "Ontology ID: " + predictedId : "Ontology ID: (none - needs mapping)";

    const candidates = parseCandidates(getPredictionValue(row, ontologyCandidatesColFor(valueCol)));
    selectEl.innerHTML = "";
    const notReviewed = document.createElement("option");
    notReviewed.value = "";
    notReviewed.textContent = "Not reviewed";
    selectEl.appendChild(notReviewed);
    if (predictedId) {
      const predOpt = document.createElement("option");
      predOpt.value = predictedId;
      predOpt.textContent = "Confirm predicted: " + predictedId;
      selectEl.appendChild(predOpt);
    }
    candidates.forEach(function(c) {
      if (c.id === predictedId) return;
      const opt = document.createElement("option");
      opt.value = c.id;
      opt.textContent = c.label + " (" + c.id + ")";
      selectEl.appendChild(opt);
    });
    const otherOpt = document.createElement("option");
    otherOpt.value = ONTO_OTHER;
    otherOpt.textContent = "Other (enter manually)";
    selectEl.appendChild(otherOpt);
    selectEl.value = "";
    if (manualEl) manualEl.style.display = "none";
  }

  function updatePredictionsForRow(row) {
    valueCols.forEach(function(col) {
      const s = safeCol(col);
      const predEl = document.getElementById("pred_" + s);
      if (predEl) {
        const val = getPredictionValue(row, col);
        predEl.textContent = val ? "BioAnalyzer predicted: " + val : predictionPlaceholder;
      }
      const trueEl = document.getElementById("true_" + s);
      if (trueEl && trueEl.tagName === "INPUT") trueEl.value = "";
      populateOntologySelect(col, row);
    });
  }

  function clearPredictions() {
    valueCols.forEach(function(col) {
      const s = safeCol(col);
      const predEl = document.getElementById("pred_" + s);
      if (predEl) predEl.textContent = predictionPlaceholder;
      const ontoCol = ontologyIdColFor(col);
      if (ontoCol) populateOntologySelect(col, null);
    });
  }

  document.addEventListener("change", function(evt) {
    if (evt.target && evt.target.classList && evt.target.classList.contains("cd-onto-select")) {
      const manualEl = document.getElementById(evt.target.id + "_manual");
      if (manualEl) manualEl.style.display = evt.target.value === ONTO_OTHER ? "" : "none";
    }
  });

  const quickSelect = document.getElementById("quick-select-pmid");
  if (quickSelect) {
    quickSelect.addEventListener("change", function() {
      const pmid = this.value;
      const fbPmid = document.getElementById("fb_pmid");
      if (fbPmid) fbPmid.value = pmid;
      if (pmid) setTitleFromPmid(pmid);
    });
  }

  const loadBtn = document.getElementById("btn-load-row");
  if (loadBtn) {
    loadBtn.addEventListener("click", function() {
      const pmid = document.getElementById("fb_pmid").value.trim();
      if (pmid) setTitleFromPmid(pmid);
    });
  }

  function escapeCsv(s) {
    if (s == null) return "";
    s = String(s);
    if (/[,"\n\r]/.test(s)) return '"' + s.replace(/"/g, '""') + '"';
    return s;
  }

  function ontologySelectValue(ontoCol) {
    const s = safeCol(ontoCol);
    const selectEl = document.getElementById("true_" + s);
    if (!selectEl) return "";
    if (selectEl.value === ONTO_OTHER) {
      const manualEl = document.getElementById("true_" + s + "_manual");
      return manualEl ? manualEl.value.trim() : "";
    }
    return selectEl.value;
  }

  function buildFeedbackCsv() {
    const pmid = document.getElementById("fb_pmid").value.trim();
    const curatorId = document.getElementById("curator_id").value.trim();
    if (!pmid || !curatorId) {
      alert("Please fill Curator ID and PMID.");
      return null;
    }
    const row = tableData.find(r => String(r.PMID) === String(pmid));
    const pred = row || {};
    const ts = new Date().toISOString();
    const rowObj = {
      "PMID": pmid,
      "curator_id": curatorId,
      "overall_verdict": document.getElementById("overall_verdict").value,
      "comment": document.getElementById("comment").value.replace(/\r?\n/g, " "),
      "timestamp": ts,
      "bioanalyzer_version": document.getElementById("bioanalyzer_version").value
    };
    valueCols.forEach(col => {
      const s = safeCol(col);
      rowObj["pred__" + s] = (pred[col] !== undefined && pred[col] !== null) ? pred[col] : "";
      const trueEl = document.getElementById("true_" + s);
      rowObj["true__" + s] = trueEl ? trueEl.value.trim() : "";
      rowObj["col_feedback__" + s] = (document.getElementById("col_fb_" + s) || {}).value || "Not reviewed";
    });
    ontologyIdCols.forEach(ontoCol => {
      const s = safeCol(ontoCol);
      rowObj["pred__" + s] = (pred[ontoCol] !== undefined && pred[ontoCol] !== null) ? pred[ontoCol] : "";
      rowObj["true__" + s] = ontologySelectValue(ontoCol);
    });
    const header = schema.map(escapeCsv).join(",");
    const line = schema.map(k => escapeCsv(rowObj[k])).join(",");
    return { csv: header + "\n" + line + "\n", pmid: pmid };
  }

  function resetFormAfterSubmit() {
    const commentEl = document.getElementById("comment");
    if (commentEl) commentEl.value = "";
    valueCols.forEach(col => {
      const s = safeCol(col);
      const t = document.getElementById("true_" + s);
      const c = document.getElementById("col_fb_" + s);
      if (t) t.value = "";
      if (c) c.value = "Not reviewed";
    });
    ontologyIdCols.forEach(ontoCol => {
      const s = safeCol(ontoCol);
      const selectEl = document.getElementById("true_" + s);
      if (selectEl) selectEl.value = "";
      const manualEl = document.getElementById("true_" + s + "_manual");
      if (manualEl) { manualEl.value = ""; manualEl.style.display = "none"; }
    });
  }

  const downloadBtn = document.getElementById("btn-download-csv");
  if (downloadBtn) {
    downloadBtn.addEventListener("click", function() {
      const out = buildFeedbackCsv();
      if (!out) return;
      const blob = new Blob([out.csv], { type: "text/csv" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "curator_feedback_" + out.pmid + ".csv";
      a.click();
      URL.revokeObjectURL(a.href);
      resetFormAfterSubmit();
    });
  }

  const submitBtn = document.getElementById("btn-submit-review");
  if (submitBtn) {
    submitBtn.addEventListener("click", function() {
      const out = buildFeedbackCsv();
      if (!out) return;
      if (!feedbackIssueUrl) {
        alert("Submit review needs the GitHub repo URL. Set GITHUB_REPO when building (e.g. in your deploy workflow or locally: export GITHUB_REPO=https://github.com/owner/repo && quarto render).");
        return;
      }
      var bodyText = "Curator feedback submission. The CSV below contains the full feedback (curator initials, comments, field-by-field validation). Maintainers can review in this issue.\n\n```csv\n" + out.csv.trim() + "\n```";
      var title = "Curator feedback submission";
      var url = feedbackIssueUrl + "?title=" + encodeURIComponent(title) + "&body=" + encodeURIComponent(bodyText);
      window.open(url, "_blank");
      resetFormAfterSubmit();
      try { sessionStorage.setItem("curator-thank-you", "1"); } catch (e) {}
      window.location.reload();
    });
  }

  var thankYouModal = document.getElementById("thank-you-modal");
  if (thankYouModal) {
    try {
      if (sessionStorage.getItem("curator-thank-you") === "1") {
        sessionStorage.removeItem("curator-thank-you");
        thankYouModal.classList.add("show");
      }
    } catch (e) {}
    var btnYes = document.getElementById("btn-continue-review");
    var btnNo = document.getElementById("btn-go-to-index");
    if (btnYes) btnYes.addEventListener("click", function() {
      thankYouModal.classList.remove("show");
      var el = document.getElementById("candidate-papers");
      if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    });
    if (btnNo) btnNo.addEventListener("click", function() {
      window.location.href = "./";
    });
  }
})();
