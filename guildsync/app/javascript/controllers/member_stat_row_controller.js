import { Controller } from "@hotwired/stimulus"

// Edit, remove, and restore OCR stat rows on member stats (GearSnapshot#data).
export default class extends Controller {
  static targets = [
    "valueBlock",
    "labelDisplay",
    "labelInput",
    "valueInput",
    "editBtn",
    "saveBtn",
    "cancelBtn",
    "removeBtn",
    "undoBtn"
  ]

  static values = {
    url: String,
    statKey: String,
    statJson: String
  }

  connect() {
    this.restoredValue = this.parseJson(this.statJsonValue)
    this.editing = false
  }

  parseJson(raw) {
    if (raw == null || raw === "") return null
    try {
      return JSON.parse(raw)
    } catch {
      return raw
    }
  }

  csrfToken() {
    const m = document.querySelector('meta[name="csrf-token"]')
    return m ? m.content : ""
  }

  toastError() {
    const holder = document.querySelector("[data-member-stats-toast-error]")
    const msg = holder?.dataset?.memberStatsToastError?.trim() || "Update failed."
    window.showToast("error", msg)
  }

  toastSaved() {
    const holder = document.querySelector("[data-member-stats-toast-saved]")
    const msg = holder?.dataset?.memberStatsToastSaved?.trim() || "Saved."
    window.showToast("success", msg)
  }

  async parseResponseBody(res) {
    try {
      return await res.json()
    } catch {
      return {}
    }
  }

  notifyRequestFailed(json) {
    if (json.message) window.showToast("error", json.message)
    else this.toastError()
  }

  isRowRemoved() {
    return (
      this.hasValueBlockTarget &&
      this.valueBlockTarget.classList.contains("line-through")
    )
  }

  startEdit(event) {
    event.preventDefault()
    if (this.editing || this.isRowRemoved()) return

    this.editing = true
    if (this.hasLabelInputTarget && this.hasLabelDisplayTarget) {
      this.labelInputTarget.value = this.labelDisplayTarget.textContent.trim()
      this.labelDisplayTarget.classList.add("hidden")
      this.labelInputTarget.classList.remove("hidden")
    }
    if (this.hasValueInputTarget && this.hasValueBlockTarget) {
      this.valueInputTarget.value = this.valueBlockTarget.textContent.trim()
      this.valueBlockTarget.classList.add("hidden")
      this.valueInputTarget.classList.remove("hidden")
    }
    if (this.hasEditBtnTarget) this.editBtnTarget.classList.add("hidden")
    if (this.hasSaveBtnTarget) this.saveBtnTarget.classList.remove("hidden")
    if (this.hasCancelBtnTarget) this.cancelBtnTarget.classList.remove("hidden")
    if (this.hasRemoveBtnTarget) this.removeBtnTarget.disabled = true
    if (this.hasUndoBtnTarget) this.undoBtnTarget.disabled = true
  }

  cancelEdit(event) {
    event.preventDefault()
    this.leaveEditMode()
  }

  leaveEditMode() {
    this.editing = false
    if (this.hasLabelInputTarget && this.hasLabelDisplayTarget) {
      this.labelInputTarget.classList.add("hidden")
      this.labelDisplayTarget.classList.remove("hidden")
    }
    if (this.hasValueInputTarget && this.hasValueBlockTarget) {
      this.valueInputTarget.classList.add("hidden")
      this.valueBlockTarget.classList.remove("hidden")
    }
    if (this.hasEditBtnTarget) this.editBtnTarget.classList.remove("hidden")
    if (this.hasSaveBtnTarget) this.saveBtnTarget.classList.add("hidden")
    if (this.hasCancelBtnTarget) this.cancelBtnTarget.classList.add("hidden")
    if (this.hasRemoveBtnTarget) this.removeBtnTarget.disabled = false
    if (this.hasUndoBtnTarget) this.undoBtnTarget.disabled = false
  }

  async saveEdit(event) {
    event.preventDefault()
    if (!this.editing || !this.hasSaveBtnTarget) return

    const label = this.hasLabelInputTarget
      ? this.labelInputTarget.value.trim()
      : ""
    const value = this.hasValueInputTarget ? this.valueInputTarget.value : ""

    this.saveBtnTarget.disabled = true
    if (this.hasCancelBtnTarget) this.cancelBtnTarget.disabled = true

    try {
      const res = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({
          op: "update",
          stat_key: this.statKeyValue,
          stat_label: label,
          stat_value: value
        })
      })

      const json = await this.parseResponseBody(res)

      if (!res.ok || !json.ok) {
        this.notifyRequestFailed(json)
        return
      }

      if (json.stat_key) this.statKeyValue = json.stat_key
      if (json.stat_json !== undefined && json.stat_json !== null) {
        const enc =
          typeof json.stat_json === "string"
            ? json.stat_json
            : JSON.stringify(json.stat_json)
        this.statJsonValue = enc
        this.restoredValue = this.parseJson(enc)
      }

      if (this.hasLabelDisplayTarget && json.display_label != null) {
        this.labelDisplayTarget.textContent = json.display_label
        this.labelDisplayTarget.title = json.display_label
      }
      if (this.hasValueBlockTarget && json.display_value != null) {
        this.valueBlockTarget.textContent = json.display_value
      }

      const line = document.getElementById("member_stats_stat_count_line")
      if (line && json.stat_count_label) line.textContent = json.stat_count_label

      this.leaveEditMode()
      this.toastSaved()
    } finally {
      if (this.hasSaveBtnTarget) this.saveBtnTarget.disabled = false
      if (this.hasCancelBtnTarget) this.cancelBtnTarget.disabled = false
    }
  }

  async remove(event) {
    event.preventDefault()
    if (this.editing) return
    await this.submitPatch({ op: "remove", stat_key: this.statKeyValue }, "remove")
  }

  async undo(event) {
    event.preventDefault()
    if (this.editing) return
    await this.submitPatch(
      { op: "restore", stat_key: this.statKeyValue, stat_value: this.restoredValue },
      "restore"
    )
  }

  async submitPatch(body, phase) {
    if (!this.hasRemoveBtnTarget) return

    this.removeBtnTarget.disabled = true
    if (this.hasUndoBtnTarget) this.undoBtnTarget.disabled = true
    if (this.hasEditBtnTarget) this.editBtnTarget.disabled = true

    try {
      const res = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify(body)
      })

      const json = await this.parseResponseBody(res)

      if (!res.ok || !json.ok) {
        this.notifyRequestFailed(json)
        return
      }

      const line = document.getElementById("member_stats_stat_count_line")
      if (line && json.stat_count_label) line.textContent = json.stat_count_label

      if (phase === "remove" && json.remaining_count === 0) {
        window.location.reload()
        return
      }

      if (phase === "remove") {
        this.removeBtnTarget.classList.add("hidden")
        if (this.hasEditBtnTarget) this.editBtnTarget.classList.add("hidden")
        if (this.hasSaveBtnTarget) this.saveBtnTarget.classList.add("hidden")
        if (this.hasCancelBtnTarget) this.cancelBtnTarget.classList.add("hidden")
        if (this.hasUndoBtnTarget) {
          this.undoBtnTarget.classList.remove("hidden")
          this.undoBtnTarget.disabled = false
        }
        if (this.hasValueBlockTarget) {
          this.valueBlockTarget.classList.add(
            "opacity-50",
            "line-through",
            "decoration-theme-secondary"
          )
        }
        if (this.hasLabelDisplayTarget) {
          this.labelDisplayTarget.classList.add("opacity-50", "line-through")
        }
        this.element.classList.add("bg-violet-500/[0.04]")
      } else {
        if (this.hasUndoBtnTarget) this.undoBtnTarget.classList.add("hidden")
        this.removeBtnTarget.classList.remove("hidden")
        if (this.hasEditBtnTarget) {
          this.editBtnTarget.classList.remove("hidden")
          this.editBtnTarget.disabled = false
        }
        if (this.hasValueBlockTarget) {
          this.valueBlockTarget.classList.remove(
            "opacity-50",
            "line-through",
            "decoration-theme-secondary"
          )
        }
        if (this.hasLabelDisplayTarget) {
          this.labelDisplayTarget.classList.remove("opacity-50", "line-through")
        }
        this.element.classList.remove("bg-violet-500/[0.04]")
      }
    } finally {
      this.removeBtnTarget.disabled = false
      if (this.hasUndoBtnTarget) this.undoBtnTarget.disabled = false
      if (this.hasEditBtnTarget) this.editBtnTarget.disabled = false
    }
  }
}
