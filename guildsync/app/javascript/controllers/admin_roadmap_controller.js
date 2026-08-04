import { Controller } from "@hotwired/stimulus"

/**
 * Admin roadmap: drag-and-drop feature request cards between status columns.
 * Uses HTML5 drag-and-drop. Sends PATCH with CSRF + credentials: 'same-origin'
 * to avoid session drop. Queues requests and reverts DOM on failure.
 */
export default class extends Controller {
  static targets = ["column", "card"]

  connect() {
    this.pendingRequests = 0
    this.dragSourceColumn = null
    this.dragSourceIndex = null
    this.setupCards()
    this.setupColumns()
    this.boundAfterStream = () => {
      this.setupCards()
    }
    document.addEventListener("turbo:after-stream-render", this.boundAfterStream)
  }

  disconnect() {
    document.removeEventListener("turbo:after-stream-render", this.boundAfterStream)
  }

  setupCards() {
    this.cardTargets.forEach((card) => {
      if (card.dataset.dndBound === "1") return
      card.dataset.dndBound = "1"
      card.setAttribute("draggable", "true")
      card.addEventListener("dragstart", this.handleDragStart.bind(this))
      card.addEventListener("dragend", this.handleDragEnd.bind(this))
    })
  }

  setupColumns() {
    this.columnTargets.forEach((col) => {
      col.addEventListener("dragover", this.handleDragOver.bind(this))
      col.addEventListener("dragleave", this.handleDragLeave.bind(this))
      col.addEventListener("drop", this.handleDrop.bind(this))
    })
  }

  handleDragStart(e) {
    const card = e.currentTarget
    const column = card.closest("[data-admin-roadmap-target='column']")
    if (!column) return
    this.dragSourceColumn = column
    this.dragSourceIndex = Array.from(column.querySelectorAll("[data-admin-roadmap-target='card']")).indexOf(card)
    e.dataTransfer.effectAllowed = "move"
    e.dataTransfer.setData("text/plain", card.dataset.featureId || "")
    card.classList.add("opacity-50", "ring-2", "ring-theme-accent")
  }

  handleDragEnd(e) {
    e.currentTarget.classList.remove("opacity-50", "ring-2", "ring-theme-accent")
    this.dragSourceColumn = null
    this.dragSourceIndex = null
  }

  handleDragOver(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"
    const col = e.currentTarget
    if (!col.classList.contains("ring-2")) {
      col.classList.add("ring-2", "ring-theme-accent", "border-theme-accent")
    }
  }

  handleDragLeave(e) {
    const col = e.currentTarget
    if (!col.contains(e.relatedTarget)) {
      col.classList.remove("ring-2", "ring-theme-accent", "border-theme-accent")
    }
  }

  handleDrop(e) {
    e.preventDefault()
    const toColumn = e.currentTarget
    toColumn.classList.remove("ring-2", "ring-theme-accent", "border-theme-accent")

    const featureId = e.dataTransfer.getData("text/plain")
    const newStatus = toColumn.dataset.status

    if (!featureId || !newStatus) return

    const card = this.element.querySelector(`[data-feature-id="${featureId}"]`)
    if (!card) return

    const fromColumn = this.dragSourceColumn
    if (fromColumn && toColumn === fromColumn) return // same column, no-op (or we could still allow reorder later)

    if (this.pendingRequests > 0) {
      this.revertCard(card, fromColumn)
      this.showError("Please wait for the current update to finish.")
      return
    }

    this.pendingRequests++
    card.classList.add("opacity-70", "pointer-events-none")

    this.updateFeatureStatus(featureId, newStatus)
      .then((res) => {
        if (res.status === 401) {
          const e = new Error("Session expired or unauthorized.")
          e.status = 401
          throw e
        }
        if (!res.ok) {
          return res.json().then((data) => {
            const e = new Error(data.error || data.errors?.join(" ") || `HTTP ${res.status}`)
            e.status = res.status
            throw e
          })
        }
        return res.json()
      })
      .then((data) => {
        if (!data.success) throw new Error(data.error || data.errors?.join(" "))
        card.classList.remove("opacity-70", "pointer-events-none")
        card.classList.add("ring-2", "ring-green-500")
        setTimeout(() => card.classList.remove("ring-2", "ring-green-500"), 1200)
        const toList = toColumn.querySelector(".space-y-3")
        if (toList) toList.appendChild(card)
      })
      .catch((err) => {
        card.classList.remove("opacity-70", "pointer-events-none")
        this.revertCard(card, fromColumn)
        const msg = err.message || "Failed to update. Please try again."
        this.showError(msg)
        if (err.status === 401) this.handleAuthError()
      })
      .finally(() => {
        this.pendingRequests--
      })
  }

  async updateFeatureStatus(featureId, newStatus) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) {
      throw new Error("Security token missing. Please refresh the page.")
    }

    const response = await fetch(`/admin/roadmap/${featureId}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      credentials: "same-origin",
      body: JSON.stringify({ status: newStatus })
    })

    if (response.status === 401) {
      const e = new Error("unauthorized")
      e.status = 401
      throw e
    }

    return response
  }

  revertCard(card, fromColumn) {
    if (!fromColumn) return
    const list = fromColumn.querySelector(".space-y-3") || fromColumn.querySelector("[data-admin-roadmap-target='card']")?.parentElement
    if (!list) return
    const cards = Array.from(list.querySelectorAll("[data-admin-roadmap-target='card']")).filter((el) => el !== card)
    const idx = this.dragSourceIndex != null ? Math.min(this.dragSourceIndex, cards.length) : 0
    const ref = cards[idx] || null
    if (ref) list.insertBefore(card, ref)
    else list.appendChild(card)
  }

  handleAuthError() {
    const returnTo = encodeURIComponent(window.location.pathname + window.location.search)
    window.location.href = `/admin/login?return_to=${returnTo}`
  }

  showError(message) {
    window.showToast('error', message)
  }
}
