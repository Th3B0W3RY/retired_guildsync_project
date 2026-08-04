import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "input",
    "preview",
    "dialog",
    "search",
    "grid",
    "emptyState",
    "loadError"
  ]

  static values = {
    iconsUrl: String,
    legacyLabels: Object
  }

  connect () {
    this.icons = null
    this.loadFailed = false
    this.renderPreview()
  }

  async open (event) {
    event.preventDefault()
    this.loadErrorTarget.classList.add("hidden")
    if (!this.icons && !this.loadFailed) {
      await this.loadIcons()
    }
    if (this.loadFailed) return

    this.searchTarget.value = ""
    this.filterAndRender()
    this.dialogTarget.showModal()
    requestAnimationFrame(() => this.searchTarget.focus())
  }

  close () {
    this.dialogTarget.close()
  }

  backdropClose (event) {
    if (event.target === this.dialogTarget) this.close()
  }

  stopDialogClick (event) {
    event.stopPropagation()
  }

  async loadIcons () {
    try {
      const res = await fetch(this.iconsUrlValue, {
        headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin"
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      this.icons = Array.isArray(data.icons) ? data.icons : []
    } catch (e) {
      this.loadFailed = true
      this.loadErrorTarget.classList.remove("hidden")
      return
    }
  }

  filterInput () {
    if (!this.hasDialogTarget || !this.dialogTarget.open) return
    this.filterAndRender()
  }

  filterAndRender () {
    if (!this.icons) return

    const q = this.searchTarget.value.trim().toLowerCase()
    const list = q
      ? this.icons.filter(([style, name, label]) => {
        const blob = `${style} ${name} ${label}`.toLowerCase()
        return blob.includes(q)
      })
      : this.icons

    this.renderGrid(list)
  }

  isValidIconName (name) {
    return typeof name === "string" && /^[a-z0-9-]+$/.test(name)
  }

  renderGrid (list) {
    this.gridTarget.replaceChildren()

    if (list.length === 0) {
      this.emptyStateTarget.classList.remove("hidden")
      return
    }
    this.emptyStateTarget.classList.add("hidden")

    const frag = document.createDocumentFragment()
    for (const [style, name, label] of list) {
      if (!this.isValidIconName(name)) continue

      const ref = `fa:${style}:${name}`
      const prefix = style === "solid" ? "fa-solid" : style === "regular" ? "fa-regular" : "fa-brands"

      const btn = document.createElement("button")
      btn.type = "button"
      btn.className =
        "flex flex-col items-center gap-1 p-3 rounded-lg border border-theme-primary bg-theme-card hover:bg-theme-hover text-theme-primary text-xs min-w-[5.5rem]"
      btn.setAttribute("aria-label", String(label))
      btn.dataset.action = "fontawesome-icon-picker#pick"
      btn.dataset.iconRef = ref

      const icon = document.createElement("span")
      icon.className = `${prefix} fa-${name} text-xl text-white`
      icon.setAttribute("aria-hidden", "true")

      const text = document.createElement("span")
      text.className = "truncate max-w-[5rem] text-center"
      text.textContent = String(label)

      btn.appendChild(icon)
      btn.appendChild(text)
      frag.appendChild(btn)
    }
    this.gridTarget.appendChild(frag)
  }

  pick (event) {
    const ref = event.currentTarget.dataset.iconRef
    if (!ref) return
    this.inputTarget.value = ref
    this.renderPreview()
    this.close()
  }

  selectLegacy (event) {
    const v = event.currentTarget.value
    if (!v) return
    this.inputTarget.value = v
    this.renderPreview()
  }

  renderPreview () {
    const v = (this.inputTarget.value || "").trim()
    if (v.startsWith("fa:")) {
      const rest = v.slice(3)
      const idx = rest.indexOf(":")
      if (idx === -1) {
        const span = document.createElement("span")
        span.className = "text-theme-secondary text-sm"
        span.textContent = v
        this.previewTarget.replaceChildren(span)
        return
      }

      const style = rest.slice(0, idx)
      const name = rest.slice(idx + 1)
      const prefix = style === "solid" ? "fa-solid" : style === "regular" ? "fa-regular" : style === "brands" ? "fa-brands" : null

      if (!prefix || !this.isValidIconName(name)) {
        const span = document.createElement("span")
        span.className = "text-theme-secondary text-sm"
        span.textContent = v
        this.previewTarget.replaceChildren(span)
        return
      }

      const icon = document.createElement("span")
      icon.className = `${prefix} fa-${name} text-xl text-white`
      icon.setAttribute("aria-hidden", "true")

      const label = document.createElement("span")
      label.className = "text-theme-secondary text-sm ml-2"
      label.textContent = v

      this.previewTarget.replaceChildren(icon, label)
      return
    }

    const legacy = this.legacyLabelsValue || {}
    const title = legacy[v] || v

    const titleSpan = document.createElement("span")
    titleSpan.className = "text-theme-secondary text-sm"
    titleSpan.textContent = String(title)

    const keySpan = document.createElement("span")
    keySpan.className = "text-xs text-theme-secondary block mt-1"
    keySpan.textContent = String(v)

    this.previewTarget.replaceChildren(titleSpan, keySpan)
  }
}
