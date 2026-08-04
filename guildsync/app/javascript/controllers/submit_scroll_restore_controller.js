import { Controller } from "@hotwired/stimulus"

/**
 * Saves window.scrollY (and optional nested scroll-container scrollTop) to sessionStorage
 * when any nested form submits, then restores on the next full page load (same key).
 */
export default class extends Controller {
  static targets = ["scrollContainer"]

  static values = {
    /** sessionStorage key; must be unique per page that uses this pattern */
    key: String,
  }

  connect() {
    this._restore()
    this._forms().forEach((form) => {
      form.addEventListener("submit", this._onSubmit, true)
    })
  }

  disconnect() {
    this._forms().forEach((form) => {
      form.removeEventListener("submit", this._onSubmit, true)
    })
  }

  _storageKey() {
    if (!this.hasKeyValue || !this.keyValue) return "gs:submitScrollRestore"
    return this.keyValue
  }

  _restore() {
    const k = this._storageKey()
    const raw = sessionStorage.getItem(k)
    if (raw == null) return
    sessionStorage.removeItem(k)
    const parsed = this._parsePayload(raw)
    if (!parsed || parsed.y == null) return
    const hasHashAnchor = typeof window.location?.hash === "string" && window.location.hash.length > 1
    requestAnimationFrame(() => {
      if (!hasHashAnchor) window.scrollTo(0, parsed.y)
      this._applyScrollTops(parsed.scrollTops)
    })
  }

  _parsePayload(raw) {
    try {
      const parsed = JSON.parse(raw)
      if (typeof parsed?.y !== "number" || !Number.isFinite(parsed.y) || parsed.y < 0) return null
      const t = typeof parsed.t === "number" ? parsed.t : 0
      if (Date.now() - t > 90_000) return null
      const result = { y: Math.floor(parsed.y) }
      if (Array.isArray(parsed.scrollTops) && parsed.scrollTops.length > 0) {
        const tops = parsed.scrollTops.map((x) =>
          typeof x === "number" && Number.isFinite(x) && x >= 0 ? Math.floor(x) : 0
        )
        if (tops.some((s) => s > 0)) result.scrollTops = tops
      }
      return result
    } catch {
      const y = Number.parseInt(raw, 10)
      if (!Number.isFinite(y) || y < 0) return null
      return { y }
    }
  }

  _applyScrollTops(scrollTops) {
    if (!Array.isArray(scrollTops) || scrollTops.length === 0) return
    const els = this.scrollContainerTargets
    if (els.length === 0) return
    const n = Math.min(scrollTops.length, els.length)
    for (let i = 0; i < n; i++) {
      els[i].scrollTop = scrollTops[i]
    }
  }

  _onSubmit = () => {
    const tops = this.scrollContainerTargets.map((el) => el.scrollTop).map((s) => Math.floor(s))
    const payload = { y: window.scrollY, t: Date.now() }
    if (tops.length > 0 && tops.some((s) => s > 0)) {
      payload.scrollTops = tops
    }
    sessionStorage.setItem(this._storageKey(), JSON.stringify(payload))
  }

  _forms() {
    return this.element.querySelectorAll("form")
  }
}
