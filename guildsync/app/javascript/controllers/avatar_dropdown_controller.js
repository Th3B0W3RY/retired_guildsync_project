import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "languageMenu"]

  connect() {
    // Close dropdown when clicking outside (use bubble phase, not capture)
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
    this.listenerAttachTimeout = null
    // Use setTimeout to ensure this fires AFTER toggle
    this.listenerAttachTimeout = setTimeout(() => {
      document.addEventListener("click", this.boundCloseOnOutsideClick)
    }, 0)
  }

  disconnect() {
    if (this.listenerAttachTimeout) {
      clearTimeout(this.listenerAttachTimeout)
      this.listenerAttachTimeout = null
    }
    document.removeEventListener("click", this.boundCloseOnOutsideClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (!this.hasMenuTarget) {
      return
    }

    const isHidden = this.menuTarget.classList.contains("hidden")

    if (isHidden) {
      this.menuTarget.classList.remove("hidden")
      this.menuTarget.style.display = "block"
      this.menuTarget.style.visibility = "visible"
      this.menuTarget.style.opacity = "1"
    } else {
      this._closeAll()
    }
  }

  toggleLanguage(event) {
    event.preventDefault()
    event.stopPropagation()

    if (!this.hasLanguageMenuTarget) return

    this.languageMenuTarget.classList.toggle("hidden")
  }

  close(event) {
    // If clicking on a link, allow navigation - don't prevent default
    const isLinkClick = event && (event.target.tagName === 'A' || event.target.closest('a'))

    if (isLinkClick) {
      this._closeAll()
      // Don't prevent default - allow link navigation
      return
    }

    // For non-link clicks, prevent default
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    this._closeAll()
  }

  closeOnOutsideClick(event) {
    // Don't close if clicking inside the dropdown container or the button
    if (this.element.contains(event.target)) {
      return
    }
    // Close if clicking outside
    if (this.hasMenuTarget && !this.menuTarget.classList.contains("hidden")) {
      this._closeAll()
    }
  }

  // Private: close main menu and reset language sub-menu
  _closeAll() {
    if (this.hasMenuTarget) {
      this.menuTarget.classList.add("hidden")
      this.menuTarget.style.display = ""
      this.menuTarget.style.visibility = ""
      this.menuTarget.style.opacity = ""
    }
    if (this.hasLanguageMenuTarget) {
      this.languageMenuTarget.classList.add("hidden")
    }
  }
}
