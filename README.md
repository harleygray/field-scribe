# FieldScribe

**A voice-first daily reporting system for landscape construction crews.** A site supervisor records ~30 seconds of audio on their phone at the end of the day. Within a minute, a structured row lands in the project's Google Sheet, the audio is filed in the project's Google Drive folder, and the page they were looking at updates in real time to confirm it. No typing, no end-of-day form, no lost context.

This README is written for someone who is technical but hasn't worked with Elixir before. The point isn't to teach the language — it's to show what each piece of the system does, why this stack was chosen, and how to run it.

## How to think about this system

If you've ever used Zapier, the mental model carries over. **Zapier sits between services and orchestrates a flow** — when a thing happens here, do this thing there, then update that other place. FieldScribe's Phoenix server plays exactly that role: it sits between the supervisor's browser, OpenAI, and Google Workspace, and orchestrates the whole sequence.

The difference is what kind of orchestrator it is.


|                                      | Zapier                             | Phoenix (Elixir)                                                                     |
| -------------------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------- |
| Serves the user-facing UI?           | No (you'd build that elsewhere)    | Yes — the page they record on is served by the same process                         |
| Holds durable state?                 | No — each task is fire-and-forget | Yes — every submission is a row in Postgres with a status that progresses           |
| Custom logic between steps?          | Limited (filters, paths)           | Unlimited — it's a real programming environment                                     |
| Retries on failure?                  | Yes, but generic                   | Yes, with custom logic — exponential backoff, snooze for rate-limit, fallback paths |
| Real-time progress back to the user? | No                                 | Yes — the page updates as each stage completes, no refresh needed                   |
| Cost model                           | Per-task, escalates with volume    | Fixed infra cost, scales with hardware                                               |

Zapier is the right tool when the workflow is simple and someone non-technical needs to own it. Phoenix is the right tool when the workflow has real engineering requirements: a UI that has to feel instant, retries that need to know *why* something failed, audio files that need to live somewhere durable for a day before being handed off, and progress updates that need to stream back to the page in milliseconds.

The expressive part is what matters here. Every stage of the pipeline can read state, decide what to do, log structured errors, and pick its retry strategy. None of that is awkward — it's just code in the same language as the rest of the application.

---

## What each component is responsible for

The system is deliberately built from three layers, each doing what it's actually good at. The seams between them are where everything comes together.

```
                     ┌────────────────────────────────────────────────┐
                     │                                                │
                     │   Browser (the supervisor's phone)             │
                     │   - records audio in the page                  │
                     │   - uploads it + form fields                   │
                     │   - watches the page update in real time       │
                     │                                                │
                     └────────────────┬───────────────────────────────┘
                                      │
                                      │ HTTP multipart upload
                                      ▼
                     ┌────────────────────────────────────────────────┐
                     │                                                │
                     │   Phoenix server  (THIS REPO)                  │
                     │   - serves the UI                              │
                     │   - stores the audio + a Postgres row          │
                     │   - orchestrates everything below              │
                     │   - streams live progress back to the browser  │
                     │                                                │
                     └─────┬──────────────────────────┬───────────────┘
                           │                          │
                           │ HTTPS (with API key)     │ HTTPS (with shared secret)
                           ▼                          ▼
              ┌────────────────────────┐    ┌──────────────────────────────┐
              │                        │    │                              │
              │   OpenAI               │    │   Google Apps Script         │
              │   - Whisper            │    │   (a small JS function       │
              │     (audio → text)     │    │    we deploy as a webhook    │
              │   - GPT                │    │    inside Google Workspace)  │
              │     (text → JSON)      │    │                              │
              │                        │    │   - writes a row to Sheets   │
              └────────────────────────┘    │   - saves audio to Drive     │
                                            │   - calls Phoenix back to    │
                                            │     confirm it's done        │
                                            │                              │
                                            └──────────────────────────────┘
```

### The browser

The page is a "LiveView" — Phoenix's way of building stateful interactive pages without a separate frontend framework. The recording control wraps the browser's built-in microphone API, so there's no Zoom-style plugin to install. When the supervisor submits, the audio uploads as a multipart file, just like attaching a file to an email.

### The Phoenix server (this repo)

This is where most of the engineering lives. Phoenix is a web framework for Elixir, similar in role to Ruby on Rails or Django, with two unusual qualities that matter here:

- **Concurrency**. Each submission gets its own lightweight process that doesn't block any other. A hundred supervisors submitting at once is a hundred independent pipelines running in parallel.
- **Real-time built in**. Phoenix has a publish-subscribe layer baked into the framework. When a pipeline stage finishes, it broadcasts a message on a topic; the LiveView is subscribed and updates the page. No polling, no webhooks back to the browser, no extra infrastructure.

The server uses a job queue called Oban that stores its work directly in Postgres. That means every report-in-flight is durable: if the server restarts halfway through a submission, the job picks up where it left off when the new process boots.

### OpenAI

Two calls per submission. First, Whisper takes the audio file and returns plain text. Second, GPT takes the text and returns a structured JSON object — what work was done, what's blocking, what materials are needed, and so on. We tell GPT *exactly* what shape we want the JSON to be in (using its "strict JSON Schema" mode), so the output can't drift off-shape between calls.

The raw transcript is always preserved alongside the structured fields, never replaced by them. The structured data is a lossy summary; the transcript is the source of truth.

### Google Apps Script

This is the trick that keeps the system simple. Apps Script is Google's own scripting environment — it's a small JavaScript function that runs *inside* Google Workspace, so it already has permission to write to your Sheets and Drive without any OAuth juggling, service accounts, or API key management.

Phoenix POSTs the structured payload to a Web App URL Apps Script gives us. Apps Script writes the row, downloads and saves the audio, then POSTs back to Phoenix to confirm. The whole interface is two HTTP calls.

The Apps Script source lives in this repo at [`priv/apps_script/Code.gs`](priv/apps_script/Code.gs) — you copy-paste it into a new Apps Script project once, set three configuration values, and the seam is wired.

---

## The pipeline, one report at a time

Here's what happens when a supervisor hits submit, with the role of each component called out.


| #  | What happens                                                                                                                            | Where                                    |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| 1  | Audio + form fields uploaded as multipart HTTP POST                                                                                     | Browser → Phoenix                       |
| 2  | Audio written to local disk, Postgres row created at status`received`, background job enqueued, page subscribed to a per-report channel | Phoenix                                  |
| 3  | Status flips to`transcribing`, page updates live                                                                                        | Phoenix → Browser                       |
| 4  | Audio sent to OpenAI Whisper, transcript stored on the row                                                                              | Phoenix → OpenAI                        |
| 5  | Status flips to`extracting`, page updates live                                                                                          | Phoenix → Browser                       |
| 6  | Transcript sent to OpenAI GPT with a strict schema, structured JSON stored on the row                                                   | Phoenix → OpenAI                        |
| 7  | Status flips to`writing`, page updates live                                                                                             | Phoenix → Browser                       |
| 8  | Phoenix POSTs the payload + a short-lived signed audio URL to Apps Script                                                               | Phoenix → Apps Script                   |
| 9  | Apps Script appends a row to the project's Sheet, downloads the audio into Drive, then POSTs back                                       | Apps Script → Sheets + Drive → Phoenix |
| 10 | Status flips to`complete`, the card shows links to the Sheet row and the Drive audio                                                    | Phoenix → Browser                       |

End-to-end on a 30-second clip: roughly 15–25 seconds.

If anything fails — Whisper times out, GPT returns malformed JSON, Apps Script returns an error — the job retries with exponential backoff. Submissions are idempotent: if a retry causes the same job to run twice, the second pass is a no-op. The supervisor's view never shows them a half-completed state; either the submission completes, or it ends in a clearly-marked `failed` state with the error captured for review.

## What happens to the audio

A common founder question: where does the voice memo actually live, and for how long?

- **Recording in the browser.** The audio never touches anyone's laptop — it's recorded in-browser and uploaded directly.
- **Local disk on the Phoenix server.** Stored as `priv/uploads/<id>.webm` while the pipeline runs. This is the working copy.
- **Google Drive (the canonical home).** Apps Script saves it into the project's Drive folder, organized by month. Once it's in Drive, that's the durable copy supervisors and PMs reference long-term.
- **TTL on the local copy.** A daily background job deletes the local file 14 days after the report completes. The database row stays — we keep the structured data and transcript indefinitely. Only the bytes go.
- **Per-browser history.** Each supervisor's phone remembers the IDs of their own submissions in `localStorage`, so they get a "your submissions" panel that persists across sessions on the same device — without us needing accounts. The links point to the Drive copy, which outlives the local one.

The audio is fetched from Phoenix by Apps Script via a URL signed with an HMAC and a 30-minute expiry, so even if the URL leaks into a log somewhere, it's useless past that window.

---

## Deploying to production

Production runs on [Fly.io](https://fly.io) in Sydney. The first-time setup is one-time:

```bash
fly launch --no-deploy --copy-config
fly postgres attach civic-forum-db --app fieldscribe --database-name fieldscribe_prod
fly secrets set \
  OPENAI_API_KEY=… \
  APPS_SCRIPT_WEBHOOK_URL=… \
  APPS_SCRIPT_SHARED_SECRET=… \
  APPS_SCRIPT_CALLBACK_SECRET=… \
  AUDIO_URL_SECRET=… \
  SECRET_KEY_BASE=$(mix phx.gen.secret)
fly deploy
```

The `civic-forum-db` step attaches the app to the existing shared Postgres cluster (the same one civic-forum and parliament-search-agent already use), creating a new logical database called `fieldscribe_prod`. Database migrations run automatically on every deploy.

After that, every push to `master` is a redeploy — `fly deploy` rebuilds the Docker image, runs migrations, and rolls the machines.

---

## Where this can go next

The MVP is intentionally small. The architecture is set up so each of the following is additive, not a rewrite:

- **More report schemas.** Adding "material requests" or "safety incidents" is one more JSON schema and one more downstream Sheet — same pipeline.
- **Triggering downstream automations.** When a `severity: high` issue comes in, send an SMS to the PM. Tag the project in HubSpot when a report's submitted. Each is one more outbound HTTP call from the pipeline. (Or, if those rules need to be edited by someone non-technical, *this* is the point at which Zapier earns its keep — by hanging off the structured payload Apps Script writes.)
- **Authentication.** Today the supervisor dropdown is the de-facto auth. Workspace SSO or a phone-based magic link slot in cleanly.
- **Project management.** Projects live in a config file today. Promote to a database table + admin UI when a second team comes online.
- **Cost tracking.** OpenAI charges per call; metering Whisper + GPT spend per project is a small addition.

See [`PROGRESS.md`](PROGRESS.md) for the full list of what's complete, what's external setup, and what's deferred.
