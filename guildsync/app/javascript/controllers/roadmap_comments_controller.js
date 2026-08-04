import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "body", "submitBtn", "list", "error"]

  connect() {
    if (this.hasFormTarget) {
      this._onSubmitEnd = (event) => {
        if (!event.detail.success || !this.hasBodyTarget) return
        this.bodyTarget.value = ""
        if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")
      }
      this.formTarget.addEventListener("turbo:submit-end", this._onSubmitEnd)
    }
  }

  disconnect() {
    if (this.hasFormTarget && this._onSubmitEnd) {
      this.formTarget.removeEventListener("turbo:submit-end", this._onSubmitEnd)
    }
  }
}
