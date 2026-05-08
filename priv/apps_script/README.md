# Apps Script — FieldScribe Web App

`Code.gs` is the deployable artefact. Phoenix POSTs reports to it; it writes
a row to your shared Google Sheet and returns the row URL synchronously in
the response body — no callback, no tunnel, no Drive upload needed.

## 1. Create the Google Sheet

1. Open [Google Sheets](https://sheets.google.com) → **Blank spreadsheet**.
2. Name it `FieldScribe Reports`.
3. Create two tabs (rename the default "Sheet1" to the first):
   - **Daily Log**
   - **Blockers Triage**
4. Copy the Sheet ID from the URL:
   `https://docs.google.com/spreadsheets/d/**<SHEET_ID>**/edit`
5. Share the Sheet with anyone you want to show the demo to.

## 2. Create the Apps Script project

1. Open [script.google.com](https://script.google.com) → **New project**.
2. Rename the project to `FieldScribe`.
3. Replace the contents of `Code.gs` with this directory's `Code.gs`.

## 3. Set Script Properties

**Project Settings** (gear icon) → **Script properties** → **Add script property**.

| Key | Value |
| --- | --- |
| `SHARED_SECRET` | Any random string — must match `APPS_SCRIPT_SHARED_SECRET` in your `.env`. Generate with `openssl rand -hex 32`. |
| `SHEET_ID` | The Sheet ID from step 1. |

## 4. Deploy as a Web App

1. **Deploy** → **New deployment**.
2. Click the gear icon next to "Select type" → **Web app**.
3. Description: `FieldScribe v1`.
4. **Execute as:** Me *(runs in your Google account, so it can write to your Sheet)*.
5. **Who has access:** Anyone *(the `SHARED_SECRET` is the actual auth boundary)*.
6. Click **Deploy** → accept the OAuth prompts (Sheets).
7. Copy the **Web app URL** — it looks like:
   `https://script.google.com/macros/s/.../exec`

## 5. Wire it up in Phoenix

Add to your `.env`:

```
APPS_SCRIPT_WEBHOOK_URL=https://script.google.com/macros/s/.../exec
APPS_SCRIPT_SHARED_SECRET=<the SHARED_SECRET value you chose above>
```

Restart the Phoenix server (`mix phx.server`), then submit a test report.
Within ~10 seconds a row should appear in the relevant Sheet tab and the
feed card will show a "→ Sheet row" link.

## Updating Code.gs

Edits require **Deploy → Manage deployments → Edit (pencil icon) → New version → Deploy**.
The Web App URL stays the same across versions.
