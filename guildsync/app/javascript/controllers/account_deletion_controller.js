import { Controller } from "@hotwired/stimulus"

const MIN_CODE_LENGTH = 8

export default class extends Controller {
  static targets = ["codeInput", "continueButton", "dialog"]

  connect() {
    this._onKeydown = this._onKeydown.bind(this)
    this.refreshContinue = this.refreshContinue.bind(this)
    this._elementFocusedBeforeModal = null

    if (this.hasCodeInputTarget) {
      this.codeInputTarget.addEventListener("input", this.refreshContinue)
    }
    this.refreshContinue()
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
    if (this.hasCodeInputTarget) {
      this.codeInputTarget.removeEventListener("input", this.refreshContinue)
    }
  }

  refreshContinue() {
    if (!this.hasContinueButtonTarget) return

    const input = this.hasCodeInputTarget ? this.codeInputTarget : null
    const codeOk = Boolean(
      input && !input.disabled && input.value.trim().length >= MIN_CODE_LENGTH
    )
    this.continueButtonTarget.disabled = !codeOk
  }

  openModal(event) {
    event.preventDefault()
    if (!this.hasDialogTarget) return
    if (this.continueButtonTarget?.disabled) return

    this._elementFocusedBeforeModal = document.activeElement
    this.dialogTarget.classList.remove("hidden")
    this.dialogTarget.classList.add("flex")
    document.addEventListener("keydown", this._onKeydown)

    const focusable = this.dialogTarget.querySelector(
      "button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
    )
    if (focusable && typeof focusable.focus === "function") {
      focusable.focus()
    }
  }

  closeModal() {
    if (!this.hasDialogTarget) return

    this.dialogTarget.classList.add("hidden")
    this.dialogTarget.classList.remove("flex")
    document.removeEventListener("keydown", this._onKeydown)

    const restore = this._elementFocusedBeforeModal
    this._elementFocusedBeforeModal = null
    if (restore && typeof restore.focus === "function") {
      restore.focus()
    }
  }

  backdropClose(event) {
    if (!this.hasDialogTarget) return
    if (event.target !== this.dialogTarget) return
    this.closeModal()
  }

  _onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.closeModal()
    }
  }
}
