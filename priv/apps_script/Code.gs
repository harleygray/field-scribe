/**
 * FieldScribe — Apps Script Web App
 *
 * Deployed as a Web App with doPost(e) as the entry point. Phoenix POSTs
 * a structured report payload here; this script writes the row to a shared
 * Google Sheet and returns the row URL in the response body.
 *
 * One-time setup (Project Settings → Script properties):
 *   SHARED_SECRET : matches APPS_SCRIPT_SHARED_SECRET on the Phoenix side
 *   SHEET_ID      : ID of your Google Sheet (the long string in the sheet URL)
 *
 * The Sheet must have two tabs: "Daily Log" and "Blockers Triage".
 * Headers and table formatting are created automatically on first write.
 * A hidden "_FieldScribeSeen" tab is created automatically as the idempotency ledger.
 */

// Column order: human-readable fields first, IDs last.
var DAILY_LOG_HEADERS = [
  "Timestamp",
  "Supervisor",
  "Project",
  "% Complete",
  "Crew Size",
  "Weather Impact",
  "Work Completed",
  "Blockers",
  "Materials Used",
  "Materials Needed",
  "Tomorrow's Plan",
  "Transcript",
  "Report ID"
];

var BLOCKERS_HEADERS = [
  "Timestamp",
  "Supervisor",
  "Project",
  "Severity",
  "Issue Summary",
  "Affected Work",
  "Requested Action",
  "Deadline Implication",
  "Transcript",
  "Report ID"
];

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);

    if (!verifySharedSecret_(body.shared_secret)) {
      return jsonResponse_({ error: "bad shared secret" });
    }

    const sheetId = PropertiesService.getScriptProperties().getProperty("SHEET_ID");
    if (!sheetId) {
      return jsonResponse_({ error: "SHEET_ID not configured in Script Properties" });
    }

    if (alreadyProcessed_(sheetId, body.report_id)) {
      return jsonResponse_({ ok: true, idempotent: true });
    }

    const sheetRowUrl = appendRow_(sheetId, body);
    markProcessed_(sheetId, body.report_id);

    return jsonResponse_({ ok: true, sheet_row_url: sheetRowUrl });
  } catch (err) {
    console.error(err);
    return jsonResponse_({ error: String(err && err.message || err) });
  }
}

function verifySharedSecret_(supplied) {
  const expected = PropertiesService.getScriptProperties().getProperty("SHARED_SECRET");
  return !!expected && supplied === expected;
}

function appendRow_(sheetId, body) {
  const ss = SpreadsheetApp.openById(sheetId);
  const isBlocker = body.report_type === "issue_blocker";
  const tabName = isBlocker ? "Blockers Triage" : "Daily Log";
  const headers = isBlocker ? BLOCKERS_HEADERS : DAILY_LOG_HEADERS;

  const sheet = ss.getSheetByName(tabName);
  if (!sheet) throw new Error("Sheet tab not found: " + tabName);

  ensureHeaders_(sheet, headers);

  const sd = body.structured_data || {};
  const ts = new Date();

  const row = isBlocker
    ? [
        ts,
        body.supervisor,
        body.project_id,
        sd.severity || "",
        sd.issue_summary || "",
        (sd.affected_work || []).join("; "),
        sd.requested_action || "",
        sd.deadline_implication || "",
        body.transcript || "",
        body.report_id
      ]
    : [
        ts,
        body.supervisor,
        body.project_id,
        sd.percent_complete == null ? "" : sd.percent_complete,
        sd.crew_size == null ? "" : sd.crew_size,
        sd.weather_impact || "",
        (sd.work_completed || []).join("; "),
        (sd.blockers || []).join("; "),
        (sd.materials_used || []).join("; "),
        (sd.materials_needed || [])
          .map(m => [m.quantity, m.unit, m.item].filter(Boolean).join(" "))
          .join("; "),
        sd.tomorrow_plan || "",
        body.transcript || "",
        body.report_id
      ];

  sheet.appendRow(row);
  const lastRow = sheet.getLastRow();
  return ss.getUrl() + "#gid=" + sheet.getSheetId() + "&range=A" + lastRow;
}

// Creates the header row with formatting if it doesn't already exist.
function ensureHeaders_(sheet, headers) {
  if (sheet.getLastRow() > 0 && sheet.getRange(1, 1).getValue() === headers[0]) return;

  // Insert a blank row at top if data already exists (unlikely on first run,
  // but handles the case where someone submitted before headers were set up).
  if (sheet.getLastRow() > 0) {
    sheet.insertRowBefore(1);
  }

  const headerRange = sheet.getRange(1, 1, 1, headers.length);
  headerRange.setValues([headers]);
  headerRange.setFontWeight("bold");
  headerRange.setBackground("#1a5276");
  headerRange.setFontColor("#ffffff");
  headerRange.setHorizontalAlignment("center");

  sheet.setFrozenRows(1);

  // Widen text-heavy columns; narrow ID column at end.
  const colWidths = headers.map(h => {
    if (h === "Transcript") return 300;
    if (h === "Report ID") return 80;
    if (["Work Completed", "Blockers", "Materials Used", "Materials Needed",
         "Issue Summary", "Affected Work", "Tomorrow's Plan"].includes(h)) return 200;
    return 120;
  });
  colWidths.forEach((w, i) => sheet.setColumnWidth(i + 1, w));
}

function alreadyProcessed_(sheetId, reportId) {
  const ledger = getOrCreateLedger_(sheetId);
  const ids = ledger.getRange(1, 1, ledger.getLastRow() || 1, 1).getValues().flat();
  return ids.indexOf(reportId) >= 0;
}

function markProcessed_(sheetId, reportId) {
  const ledger = getOrCreateLedger_(sheetId);
  ledger.appendRow([reportId, new Date()]);
}

function getOrCreateLedger_(sheetId) {
  const ss = SpreadsheetApp.openById(sheetId);
  let ledger = ss.getSheetByName("_FieldScribeSeen");
  if (!ledger) {
    ledger = ss.insertSheet("_FieldScribeSeen");
    ledger.hideSheet();
  }
  return ledger;
}

function jsonResponse_(body) {
  return ContentService.createTextOutput(JSON.stringify(body))
    .setMimeType(ContentService.MimeType.JSON);
}
