import { Controller } from "@hotwired/stimulus"

/**
 * Vertical drag-and-drop reorder for admin lists; PATCHes order[] to reorder_url.
 */
export default class extends Controller {
  static targets = ["row"]
  static values = { reorderUrl: String }

  connect() {
    this.dragId = null
    this.rowTargets.forEach((row) => {
      if (row.dataset.dndBound === "1") return
      row.dataset.dndBound = "1"
      row.setAttribute("draggable", "true")
      row.addEventListener("dragstart", (e) => this.onDragStart(e))
      row.addEventListener("dragend", (e) => this.onDragEnd(e))
      row.addEventListener("dragover", (e) => this.onDragOver(e))
      row.addEventListener("drop", (e) => this.onDrop(e))
    })
  }

  onDragStart(e) {
    const row = e.currentTarget
    this.dragId = row.dataset.id
    e.dataTransfer.effectAllowed = "move"
    e.dataTransfer.setData("text/plain", row.dataset.id)
    row.classList.add("opacity-50", "ring-2", "ring-violet-500/60")
  }

  onDragEnd(e) {
    e.currentTarget.classList.remove("opacity-50", "ring-2", "ring-violet-500/60")
    this.dragId = null
  }

  onDragOver(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"
  }

  onDrop(e) {
    e.preventDefault()
    const targetRow = e.currentTarget
    const dragged = this.element.querySelector(`[data-id="${this.dragId}"]`)
    if (!dragged || dragged === targetRow) return

    const rect = targetRow.getBoundingClientRect()
    const before = e.clientY < rect.top + rect.height / 2
    if (before) {
      targetRow.parentNode.insertBefore(dragged, targetRow)
    } else {
      targetRow.parentNode.insertBefore(dragged, targetRow.nextSibling)
    }

    this.persistOrder()
  }

  async persistOrder() {
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const order = this.rowTargets.map((r) => r.dataset.id)
    const body = new FormData()
    order.forEach((id) => body.append("order[]", id))

    const res = await fetch(this.reorderUrlValue, {
      method: "PATCH",
      headers: token ? { "X-CSRF-Token": token } : {},
      body,
      credentials: "same-origin"
    })
    if (!res.ok) {
      window.location.reload()
    }
  }
}
