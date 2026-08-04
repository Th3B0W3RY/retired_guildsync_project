import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 20000 },
    url: { type: String, default: "/dashboard/stats" }
  }

  static targets = ["container"]

  connect() {
    this.boundVisibility = this.onVisibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.boundVisibility)
    this.startPolling()
    void this.refresh()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibility)
    this.stopPolling()
  }

  startPolling() {
    this.stopPolling()
    if (document.visibilityState === "hidden") return
    this.pollTimer = setInterval(() => this.refresh(), this.intervalValue)
  }

  stopPolling() {
    if (this.pollTimer) clearInterval(this.pollTimer)
    this.pollTimer = null
  }

  onVisibilityChange() {
    if (document.visibilityState === "hidden") {
      this.stopPolling()
    } else {
      this.startPolling()
      void this.refresh()
    }
  }

  async refresh() {
    if (!this.hasContainerTarget) return

    try {
      const res = await fetch(this.urlValue, {
        headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" }
      })

      if (res.ok) {
        this.containerTarget.innerHTML = await res.text()
      }
    } catch (_error) {
      // Ignore transient poll failures and retry next interval.
    }
  }
}
