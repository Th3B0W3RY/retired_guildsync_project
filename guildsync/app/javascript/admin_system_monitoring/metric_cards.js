/**
 * Renders admin system monitoring metric cards (text-only grids).
 * DOM-only; no network. Keeps XSS-safe text nodes (no innerHTML for values).
 */
export class MetricCardsRenderer {
  static formatMB(n) {
    return n != null ? `${n.toFixed(1)} MB` : "—"
  }

  static formatPct(n) {
    return n != null ? `${n.toFixed(1)}%` : "—"
  }

  static setMetricGrid(element, rows, errorMessage) {
    if (!element) return
    while (element.firstChild) element.removeChild(element.firstChild)
    if (errorMessage) {
      element.className = "text-theme-secondary text-sm break-words min-h-[1.25rem]"
      element.textContent = errorMessage
      return
    }
    element.className = "text-sm break-words min-h-[1.25rem]"
    if (!rows || !rows.length) {
      element.className = "text-theme-secondary text-sm break-words min-h-[1.25rem]"
      element.textContent = "—"
      return
    }
    const grid = document.createElement("div")
    grid.className = "grid grid-cols-[minmax(0,1fr)_auto] gap-x-3 gap-y-1 items-baseline"
    rows.forEach((r) => {
      const l = document.createElement("div")
      l.className = "text-theme-secondary"
      l.textContent = r[0]
      const v = document.createElement("div")
      v.className = "text-right tabular-nums text-theme-primary shrink-0"
      v.textContent = r[1]
      grid.appendChild(l)
      grid.appendChild(v)
    })
    element.appendChild(grid)
  }

  static renderMemory(el, m, L = {}) {
    if (!m) {
      this.setMetricGrid(el, null, null)
      return
    }
    if (m.error) {
      this.setMetricGrid(el, null, m.error)
      return
    }
    const rows = []
    if (m.process_rss_mb != null) rows.push([L.process_rss || "Process RSS", this.formatMB(m.process_rss_mb)])
    if (m.system_total_mb != null) rows.push([L.total || "Total", this.formatMB(m.system_total_mb)])
    if (m.system_used_mb != null) rows.push([L.used || "Used", this.formatMB(m.system_used_mb)])
    if (m.system_available_mb != null) rows.push([L.available || "Available", this.formatMB(m.system_available_mb)])
    this.setMetricGrid(el, rows, null)
  }

  static renderCpu(el, c, L = {}) {
    if (!c) {
      this.setMetricGrid(el, null, null)
      return
    }
    if (c.error) {
      this.setMetricGrid(el, null, c.error)
      return
    }
    const load = c.load_average || []
    const val = load.length ? load.map((v) => v.toFixed(2)).join(" / ") : "—"
    this.setMetricGrid(el, [[L.load_avg || "Load avg (1 / 5 / 15m)", val]], null)
  }

  static renderDisk(el, d, L = {}) {
    if (!d) {
      this.setMetricGrid(el, null, null)
      return
    }
    if (d.error) {
      this.setMetricGrid(el, null, d.error)
      return
    }
    const rows = []
    if (d.used_mb != null) rows.push([L.used || "Used", this.formatMB(d.used_mb)])
    if (d.available_mb != null) rows.push([L.free || "Free", this.formatMB(d.available_mb)])
    if (d.used_percent != null) rows.push([L.usage || "Usage", this.formatPct(d.used_percent)])
    this.setMetricGrid(el, rows, null)
  }

  static renderSidekiq(el, s, L = {}) {
    if (!s) {
      this.setMetricGrid(el, null, null)
      return
    }
    if (s.error) {
      this.setMetricGrid(el, null, s.error)
      return
    }
    const rows = []
    if (s.processed != null) rows.push([L.processed || "Processed", String(s.processed)])
    if (s.failed != null) rows.push([L.failed || "Failed", String(s.failed)])
    if (s.busy != null) rows.push([L.busy || "Busy", String(s.busy)])
    if (s.enqueued != null) rows.push([L.enqueued || "Enqueued", String(s.enqueued)])
    if (s.scheduled_size != null) rows.push([L.scheduled || "Scheduled", String(s.scheduled_size)])
    this.setMetricGrid(el, rows, null)
  }

  static renderPuma(el, p, L = {}) {
    if (!p) {
      this.setMetricGrid(el, null, null)
      return
    }
    if (p.error) {
      this.setMetricGrid(el, null, p.error)
      return
    }
    const rows = []
    if (p.workers != null) rows.push([L.workers || "Workers", String(p.workers)])
    if (p.phase) rows.push([L.phase || "Phase", String(p.phase)])
    this.setMetricGrid(el, rows, null)
  }

  static renderDatabase(el, db, L = {}) {
    if (!db) {
      this.setMetricGrid(el, null, null)
      return
    }
    if (db.error) {
      this.setMetricGrid(el, null, db.error)
      return
    }
    const rows = []
    if (db.pool_size != null) rows.push([L.pool || "Pool", String(db.pool_size)])
    if (db.connections != null) rows.push([L.connections || "Connections", String(db.connections)])
    if (db.in_use != null) rows.push([L.in_use || "In use", String(db.in_use)])
    this.setMetricGrid(el, rows, null)
  }

  /**
   * @param {object} metricRows — nested labels from I18n (admin.system_monitoring.metric_rows)
   */
  static applyAll(data, targets, metricRows = {}) {
    const mr = metricRows || {}
    this.renderMemory(targets.memory, data.memory, mr.memory || {})
    this.renderCpu(targets.cpu, data.cpu, mr.cpu || {})
    this.renderDisk(targets.disk, data.disk, mr.disk || {})
    this.renderSidekiq(targets.sidekiq, data.sidekiq, mr.sidekiq || {})
    this.renderPuma(targets.puma, data.puma, mr.puma || {})
    this.renderDatabase(targets.database, data.database, mr.database || {})
  }
}
