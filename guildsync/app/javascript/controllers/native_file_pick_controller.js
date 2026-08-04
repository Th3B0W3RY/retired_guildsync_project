import { Controller } from "@hotwired/stimulus"

// Visible button triggers hidden file input; shows chosen filename (alliance logo, etc.).
export default class extends Controller {
  static targets = ["input", "filename"]

  connect() {
    if (this.hasFilenameTarget && this.filenameTarget.dataset.emptyText) {
      this.filenameTarget.textContent = this.filenameTarget.dataset.emptyText
    }
  }

  pick(event) {
    event.preventDefault()
    this.inputTarget.click()
  }

  changed() {
    if (!this.hasFilenameTarget) return
    const file = this.inputTarget.files?.[0]
    const empty = this.filenameTarget.dataset.emptyText || ""
    this.filenameTarget.textContent = file ? file.name : empty
  }
}
