// RecentSubmissions hook — on mount, reads the per-device list of
// submitted report IDs from localStorage and pushes them to the
// LiveView so it can hydrate transcript previews + Drive links.

const STORAGE_KEY = "fieldscribe:submissions"

const RecentSubmissions = {
  mounted() {
    try {
      const entries = JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]")
      const ids = entries.map(e => e.id).filter(Boolean)
      if (ids.length > 0) {
        this.pushEvent("hydrate_recent", {ids})
      }
    } catch (err) {
      console.warn("recent_submissions hydrate failed", err)
    }
  }
}

export default RecentSubmissions
