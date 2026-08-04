import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
    setTimeout(() => {
      document.addEventListener("click", this.boundCloseOnOutsideClick)
    }, 0)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnOutsideClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (!this.hasMenuTarget) return

    const isHidden = this.menuTarget.classList.contains("hidden")
    if (isHidden) {
      this.menuTarget.classList.remove("hidden")
    } else {
      this.menuTarget.classList.add("hidden")
    }
  }

  closeOnOutsideClick(event) {
    if (this.element.contains(event.target)) return
    if (this.hasMenuTarget && !this.menuTarget.classList.contains("hidden")) {
      this.menuTarget.classList.add("hidden")
    }
  }
}
