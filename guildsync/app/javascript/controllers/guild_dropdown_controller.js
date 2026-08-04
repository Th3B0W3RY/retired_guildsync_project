import { Controller } from "@hotwired/stimulus"

/**
 * Controls collapsible dropdown sections in the sidebar (Universal Menu,
 * individual guild menus). Persists open/closed state to localStorage so
 * it survives page refreshes and Turbo Drive navigations.
 *
 * State may already be pre-applied to the DOM by sidebar_scroll_controller's
 * turbo:before-render hook. In that case connect() simply confirms the
 * visual state matches and skips redundant DOM writes.
 */
export default class extends Controller {
  static targets = ["menu", "button", "icon"]

  connect() {
    const guildId = this.element.dataset.guildId
    if (!guildId || !this.hasMenuTarget) return

    // Universal menu defaults open (Figma shows links + Discord status); guild menus default closed.
    const stored = localStorage.getItem(`dropdown_${guildId}_open`)
    const shouldBeOpen =
      guildId === "universal-menu" ? stored !== "false" : stored === "true"
    const isCurrentlyOpen = !this.menuTarget.classList.contains("hidden")

    if (shouldBeOpen && !isCurrentlyOpen) {
      this.menuTarget.classList.remove("hidden")
      if (this.hasIconTarget) this.iconTarget.classList.add("rotate-180")
    } else if (!shouldBeOpen && isCurrentlyOpen) {
      this.menuTarget.classList.add("hidden")
      if (this.hasIconTarget) this.iconTarget.classList.remove("rotate-180")
    }
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasMenuTarget) return

    const isHidden = this.menuTarget.classList.contains("hidden")

    if (isHidden) {
      this.menuTarget.classList.remove("hidden")
      if (this.hasIconTarget) this.iconTarget.classList.add("rotate-180")
      this.saveState(true)
    } else {
      this.menuTarget.classList.add("hidden")
      if (this.hasIconTarget) this.iconTarget.classList.remove("rotate-180")
      this.saveState(false)
    }
  }

  saveState(open) {
    const guildId = this.element.dataset.guildId
    if (!guildId) return
    try {
      const key = `dropdown_${guildId}_open`
      // Universal menu: default-open semantics require explicit "false" when closed.
      if (guildId === "universal-menu") {
        localStorage.setItem(key, open ? "true" : "false")
      } else if (open) {
        localStorage.setItem(key, "true")
      } else {
        localStorage.removeItem(key)
      }
    } catch (_) { /* quota exceeded */ }
  }
}
