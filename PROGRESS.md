# FieldScribe — Progress

## Status

✅ **End-to-end pipeline working** — voice report → transcription → AI extraction → Google Sheets row → feed card shows "→ Sheet row" link.
✅ **Local dev runs** — `mix phx.server` on `http://localhost:3999`.
🟡 **Fly.io deploy not yet done** — scaffold in place, not launched.

---

## Architecture changes from original plan

### Apps Script integration (simplified)

The original plan had Apps Script as a standalone Web App with:
- Per-project `PROJECTS_JSON` configuration
- Drive audio file upload
- Callback POST from Apps Script back to Phoenix (required ngrok in dev)

**What it is now:**
- Single shared Google Sheet (two tabs: Daily Log / Blockers Triage)
- Phoenix POSTs to Apps Script `/exec`; Google returns a 302 to an echo URL; Phoenix GETs that URL; Apps Script runs `doPost` and returns the Sheet row URL synchronously in the response body
- No Drive upload, no callback, no tunnel needed for local dev
- Sheet rows have formatted headers (auto-created on first write), readable column order (IDs at end)
- Idempotency ledger (`_FieldScribeSeen` hidden tab) prevents duplicate rows on Oban retries

**Env vars required (simplified from original):**
```
APPS_SCRIPT_WEBHOOK_URL=https://script.google.com/macros/s/.../exec
APPS_SCRIPT_SHARED_SECRET=<matches SHARED_SECRET Script Property>
```

### Removed components
- `WebhooksController` + `/api/webhooks/apps_script_callback` route (callback pattern dropped)
- `AudioController` + `/audio/:id/:token` route (Drive upload dropped, signed URL signing removed)
- `APPS_SCRIPT_CALLBACK_SECRET` and `AUDIO_URL_SECRET` env vars (no longer needed)

---

## What's implemented

### Backend
- `FieldScribe.Reports` context with PubSub broadcasts
- `FieldScribe.Reports.Report` schema with full validation
- `FieldScribe.Projects` reading from `config :fieldscribe, :projects`
- `FieldScribe.Storage` — `priv/uploads/<id>.webm` abstraction
- `FieldScribe.AI.OpenAI` — Whisper + GPT calls via Req, strict `response_format: json_schema`
- `FieldScribe.AI.Schemas` — Schema A (daily progress) + Schema B (issue/blocker)
- `FieldScribe.Integrations.AppsScript` — POST to `/exec`, follow 302 with GET to echo URL, read Sheet row URL from synchronous response; structured logging at each step
- `FieldScribe.Workers.ReportPipeline` — stage machine: `received → transcribing → extracting → writing → persisted → complete`; defensive `rescue` clause logs and surfaces exceptions rather than silently retrying
- `FieldScribe.Workers.AudioRetention` — daily Oban Cron (03:17 UTC), 14-day TTL on local audio files

### Web
- Single `FieldScribeWeb.FieldScribeLive` with 3 panels:
  - **Form**: project + supervisor + report type + recorder + submit
  - **Pipeline activity**: live stream of report cards; transcript preview, expandable JSON, color-coded error log, "→ Sheet row" link once complete
  - **Architecture**: animated SVG + explainer tabs
- "Your submissions" panel hydrated from `localStorage`
- Recorder JS hook (`assets/js/hooks/recorder.js`)
- RecentSubmissions JS hook (`assets/js/hooks/recent_submissions.js`)
- API: `POST /api/reports` (multipart), `GET /api/reports/:id`

### Apps Script (`priv/apps_script/Code.gs`)
- `doPost(e)` with shared-secret verification
- Idempotency via `_FieldScribeSeen` hidden ledger tab
- Auto-creates header row with formatting on first write (dark blue header, frozen row 1, column widths preset)
- Column order: human-readable fields first, Report ID last
- Writes to **Daily Log** or **Blockers Triage** tab based on `report_type`
- Returns `{ ok: true, sheet_row_url: "..." }` synchronously

### Tests
- 16 tests, 0 failures
- `test/fieldscribe/projects_test.exs` — 5 tests
- `test/fieldscribe/reports_test.exs` — 5 tests
- `test/fieldscribe/workers/report_pipeline_test.exs` — 2 tests
- `test/fieldscribe/integrations/apps_script_test.exs` — placeholder (HTTP calls not mocked)
- Phoenix-generated error tests retained

### Deployment scaffold
- `Dockerfile`, `fly.toml` (`app=fieldscribe`, `primary_region=syd`), `rel/env.sh.eex`, `lib/fieldscribe/release.ex`

---

## What's still to do

### External / setup steps (user-driven)
- [x] Deploy `priv/apps_script/Code.gs` as Web App ✅
- [x] Set Script Properties: `SHARED_SECRET`, `SHEET_ID` ✅
- [x] Create `Daily Log` and `Blockers Triage` tabs ✅ (headers auto-created on first write)
- [ ] First Fly deploy: `fly launch --no-deploy --copy-config` → `fly postgres attach civic-forum-db --app fieldscribe --database-name fieldscribe_prod` → `fly secrets set …` → `fly deploy`
- [ ] Confirm end-to-end on deployed environment

### Code polish
- [ ] **Empty-state** for the feed when `@streams.reports` is empty
- [ ] **`<title>`** assign — currently uses Phoenix default
- [ ] **Idle replay** of stage animation when page is quiet (`active_stage` resets to nil)
- [ ] **Mobile layout pass** — grid collapses under 960px but untested on real phone

### Test coverage gaps
- [ ] `Api.ReportsController` multipart integration test
- [ ] `FieldScribeLive` render + handle_info smoke test
- [ ] `AudioRetention` worker test
- [ ] Apps Script integration test with mocked HTTP

### Out of scope for MVP
- Authentication (supervisor dropdown is de-facto auth; Workspace SSO or phone magic link in v2)
- Admin UI for project/Sheet management (currently config-only)
- Schema C — Material requests
- Multi-language transcription
- Cost tracking / per-project quotas
- S3/Tigris storage (`audio_path` key already opaque for future swap)
