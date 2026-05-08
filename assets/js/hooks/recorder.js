// Recorder hook — wraps the browser MediaRecorder, then POSTs the audio
// blob plus the form fields to /api/reports as multipart, then pushes
// `report_started` to the LiveView so a placeholder card appears.

const STORAGE_KEY = "fieldscribe:submissions"
const MAX_REMEMBERED = 30

const Recorder = {
  mounted() {
    this.chunks = []
    this.mediaRecorder = null
    this.blob = null

    this.recordBtn = this.el.querySelector("#fs-record-btn")
    this.statusEl = this.el.querySelector("#fs-record-status")
    this.previewEl = this.el.querySelector("#fs-record-preview")
    this.submitBtn = this.el.querySelector("#fs-submit-btn")

    this.recordBtn.addEventListener("click", () => this.toggleRecording())
    this.submitBtn.addEventListener("click", () => this.submit())
  },

  destroyed() {
    if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
      this.mediaRecorder.stop()
    }
  },

  async toggleRecording() {
    if (this.mediaRecorder && this.mediaRecorder.state === "recording") {
      this.mediaRecorder.stop()
      this.recordBtn.classList.remove("recorder__btn--recording")
      this.recordBtn.querySelector(".recorder__label").textContent = "Tap to record"
      this.statusEl.textContent = "Stopped."
      return
    }

    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      this.statusEl.textContent = "Microphone access not available in this browser."
      return
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({audio: true})
      this.chunks = []
      const mimeType = MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : ""
      this.mediaRecorder = new MediaRecorder(stream, mimeType ? {mimeType} : {})

      this.mediaRecorder.addEventListener("dataavailable", e => {
        if (e.data.size > 0) this.chunks.push(e.data)
      })
      this.mediaRecorder.addEventListener("stop", () => {
        this.blob = new Blob(this.chunks, {type: mimeType || "audio/webm"})
        const url = URL.createObjectURL(this.blob)
        this.previewEl.hidden = false
        this.previewEl.src = url
        this.submitBtn.disabled = false
        // Also stop all mic tracks so the browser indicator goes away.
        stream.getTracks().forEach(t => t.stop())
      })

      this.mediaRecorder.start()
      this.recordBtn.classList.add("recorder__btn--recording")
      this.recordBtn.querySelector(".recorder__label").textContent = "Tap to stop"
      this.statusEl.textContent = "Recording…"
    } catch (err) {
      console.error(err)
      this.statusEl.textContent = micErrorMessage(err)
    }
  },

  async submit() {
    if (!this.blob) {
      this.statusEl.textContent = "Record something first."
      return
    }
    this.submitBtn.disabled = true
    this.statusEl.textContent = "Uploading…"

    const fd = new FormData()
    fd.append("project_id", this.el.querySelector("[name=project_id]").value)
    fd.append("supervisor", this.el.querySelector("[name=supervisor]").value)
    const reportType = this.el.querySelector("[name=report_type]:checked")
    fd.append("report_type", reportType ? reportType.value : "daily_progress")
    fd.append("audio", this.blob, "report.webm")

    try {
      const res = await fetch("/api/reports", {method: "POST", body: fd})
      if (!res.ok) {
        throw new Error(await parseSubmitError(res))
      }
      const json = await res.json()
      this.statusEl.textContent = "Submitted ✓"
      this.recordBtn.classList.remove("recorder__btn--recording")
      this.recordBtn.querySelector(".recorder__label").textContent = "Tap to record"
      this.previewEl.hidden = true
      this.previewEl.src = ""
      this.blob = null

      this.pushEventTo(this.el, "report_started", {id: json.id})
      this.remember({
        id: json.id,
        project_id: fd.get("project_id"),
        supervisor: fd.get("supervisor"),
        report_type: fd.get("report_type"),
        submitted_at: new Date().toISOString()
      })
    } catch (err) {
      console.error(err)
      this.statusEl.textContent = err.message
      this.submitBtn.disabled = false
    }
  },

  remember(entry) {
    try {
      const existing = JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]")
      const next = [entry, ...existing.filter(e => e.id !== entry.id)].slice(0, MAX_REMEMBERED)
      localStorage.setItem(STORAGE_KEY, JSON.stringify(next))
    } catch (err) {
      console.warn("localStorage write failed", err)
    }
  }
}

function micErrorMessage(err) {
  switch (err && err.name) {
    case "NotAllowedError":
    case "PermissionDeniedError":
      return "Microphone permission was denied. Open your browser's site settings to allow it, then reload the page."
    case "NotFoundError":
    case "DevicesNotFoundError":
      return "No microphone detected. Connect one and try again."
    case "NotReadableError":
    case "TrackStartError":
      return "The microphone is in use by another app. Close that app and try again."
    case "OverconstrainedError":
      return "No microphone matched the requested settings."
    default:
      return "Couldn't access the microphone: " + ((err && (err.message || err.name)) || "unknown error")
  }
}

async function parseSubmitError(res) {
  let body
  try {
    body = await res.json()
  } catch {
    return `Server rejected the upload (HTTP ${res.status}).`
  }

  if (body && body.error === "validation_failed" && body.details) {
    const parts = []
    for (const [field, msgs] of Object.entries(body.details)) {
      const list = Array.isArray(msgs) ? msgs : [msgs]
      parts.push(`${field}: ${list.join(", ")}`)
    }
    return parts.length ? parts.join(" · ") : `Validation failed (HTTP ${res.status}).`
  }

  if (body && body.error) return body.error

  return `Server rejected the upload (HTTP ${res.status}).`
}

export default Recorder
