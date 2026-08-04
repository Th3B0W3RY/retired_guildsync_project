import { Controller } from "@hotwired/stimulus"
import { MetricCardsRenderer } from "../admin_system_monitoring/metric_cards"
import { SnapshotChartsPanel } from "../admin_system_monitoring/snapshot_charts"

/** Admin /system-monitoring: manual refresh only; snapshot charts; no polling. */
export default class extends Controller {
  static values = { url: String, i18n: Object }

  static targets = [
    "lastUpdated",
    "refreshBtn",
    "memoryContent",
    "cpuContent",
    "diskContent",
    "sidekiqContent",
    "pumaContent",
    "databaseContent",
    "memoryCanvas",
    "loadCanvas",
  ]

  connect() {
    const i18n = this.i18nValue || {}
    const charts = i18n.charts || {}
    this.panel = new SnapshotChartsPanel(this.memoryCanvasTarget, this.loadCanvasTarget, {
      rss_mb: charts.rss_mb,
      load_1m: charts.load_1m,
    })
    this.lastUpdatedTarget.textContent = i18n.click_refresh_to_load || ""
  }

  disconnect() {
    this.panel?.destroy()
    this.panel = null
  }

  refresh(event) {
    event?.preventDefault()
    this.fetchAndRender()
  }

  async fetchAndRender() {
    const i18n = this.i18nValue || {}
    const btn = this.refreshBtnTarget
    btn.disabled = true
    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
      })
      if (!res.ok) {
        const tmpl = i18n.error_http || "Error: HTTP %{status}"
        this.lastUpdatedTarget.textContent = tmpl.replace("%{status}", String(res.status))
        return
      }
      const data = await res.json()
      const collected = data.collected_at || ""
      const ts = String(collected).replace("T", " ").substring(0, 19)
      const updatedTmpl = i18n.updated_at || "Updated: %{timestamp}"
      this.lastUpdatedTarget.textContent = updatedTmpl.replace("%{timestamp}", ts)

      MetricCardsRenderer.applyAll(data, {
        memory: this.memoryContentTarget,
        cpu: this.cpuContentTarget,
        disk: this.diskContentTarget,
        sidekiq: this.sidekiqContentTarget,
        puma: this.pumaContentTarget,
        database: this.databaseContentTarget,
      }, i18n.metric_rows || {})

      const rssMb = data.memory?.process_rss_mb ?? null
      const load = data.cpu?.load_average
      const load1m = Array.isArray(load) && load[0] != null ? load[0] : null
      const timeLabel = collected ? String(collected).replace("T", " ").substring(11, 19) : "—"

      this.panel.setSnapshot({ rssMb, load1m, timeLabel })
    } catch (e) {
      this.lastUpdatedTarget.textContent = i18n.error_loading || ""
      console.error(e)
    } finally {
      btn.disabled = false
    }
  }
}
