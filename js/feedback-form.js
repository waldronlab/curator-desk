(function() {
  const schema = [
    "PMID","curator_id","overall_verdict","comment","timestamp","bioanalyzer_version",
    "pred__Host_Species_Status","pred__Body_Site_Status","pred__Condition_Status",
    "pred__Sequencing_Type_Status","pred__Sample_Size_Status",
    "true__Host_Species_Status","true__Body_Site_Status","true__Condition_Status",
    "true__Sequencing_Type_Status","true__Sample_Size_Status",
    "col_feedback__Host_Species_Status","col_feedback__Body_Site_Status","col_feedback__Condition_Status",
    "col_feedback__Sequencing_Type_Status","col_feedback__Sample_Size_Status"
  ];
  const statusCols = [
    "Host Species Status","Body Site Status","Condition Status",
    "Sequencing Type Status","Sample Size Status"
  ];
  const safeCol = c => c.replace(/ /g, "_");

  let tableData = [];
  const el = document.getElementById("curator-table-data");
  if (el) try { tableData = JSON.parse(el.textContent); } catch (_) {}

  const configEl = document.getElementById("curator-config");
  let feedbackIssueUrl = "";
  if (configEl) {
    try {
      const cfg = JSON.parse(configEl.textContent);
      if (cfg.curator_id_default) document.getElementById("curator_id").value = cfg.curator_id_default;
      const verEl = document.getElementById("bioanalyzer_version");
      if (verEl) verEl.value = cfg.bioanalyzer_version_default || "1.0.0";
      if (cfg.feedback_issue_url) feedbackIssueUrl = cfg.feedback_issue_url;
    } catch (_) {}
  }
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

  const predictionPlaceholder = "Select a PMID above and click Load row to see BioAnalyzer's prediction.";

  function updatePredictionsForRow(row) {
    statusCols.forEach(function(col) {
      const s = safeCol(col);
      const predEl = document.getElementById("pred_" + s);
      if (!predEl) return;
      const val = getPredictionValue(row, col);
      predEl.textContent = val ? "BioAnalyzer predicted: " + val : predictionPlaceholder;
      predEl.className = "bioanalyzer-pred " + (val ? "pred-" + val.toUpperCase().replace(/\s+/g, "_") : "text-muted");
    });
  }

  function clearPredictions() {
    statusCols.forEach(function(col) {
      const s = safeCol(col);
      const predEl = document.getElementById("pred_" + s);
      if (predEl) {
        predEl.textContent = predictionPlaceholder;
        predEl.className = "bioanalyzer-pred text-muted";
      }
    });
  }

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
    statusCols.forEach(col => {
      const s = safeCol(col);
      rowObj["pred__" + s] = (pred[col] !== undefined && pred[col] !== null) ? pred[col] : "";
      rowObj["true__" + s] = (document.getElementById("true_" + s) || {}).value || "Not reviewed";
      rowObj["col_feedback__" + s] = (document.getElementById("col_fb_" + s) || {}).value || "Not reviewed";
    });
    const header = schema.map(escapeCsv).join(",");
    const line = schema.map(k => escapeCsv(rowObj[k])).join(",");
    return { csv: header + "\n" + line + "\n", pmid: pmid };
  }

  function resetFormAfterSubmit() {
    const commentEl = document.getElementById("comment");
    if (commentEl) commentEl.value = "";
    statusCols.forEach(col => {
      const s = safeCol(col);
      const t = document.getElementById("true_" + s);
      const c = document.getElementById("col_fb_" + s);
      if (t) t.value = "Not reviewed";
      if (c) c.value = "Not reviewed";
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
