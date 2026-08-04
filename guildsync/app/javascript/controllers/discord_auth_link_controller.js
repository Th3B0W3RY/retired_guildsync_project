/**
 * Forces a full browser navigation when the Discord OAuth link is clicked.
 * Fixes the issue where "Sign in with Discord" does nothing after sign-out
 * until the page is refreshed (Turbo Drive can leave the link in a broken state).
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundClick = this.handleClick.bind(this)
    this.element.addEventListener("click", this.boundClick)
  }

  disconnect() {
    this.element.removeEventListener("click", this.boundClick)
  }

  handleClick(event) {
    const href = this.element.href || this.element.getAttribute("href")
    if (href) {
      event.preventDefault()
      event.stopPropagation()
      window.location.href = href
    }
  }
}
