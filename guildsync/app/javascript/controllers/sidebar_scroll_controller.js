import { Controller } from "@hotwired/stimulus"

/**
 * Preserves sidebar scroll position and dropdown states across
 * Turbo Drive navigations and hard refreshes using localStorage.
 *
 * Uses turbo:before-render to pre-apply state to the incoming body
 * before it is inserted, eliminating the visual "jump" that occurs
 * when state is restored asynchronously after paint.
 */
export default class extends Controller {
  static values = {
    storageKey: { type: String, default: "sidebar_scroll_position" }
  }

  connect() {
    this.restoreScrollPosition()
    this.restoreDetailsStates()

    this.scrollTimeout = null
    this.boundHandleScroll = this.handleScroll.bind(this)
    this.element.addEventListener("scroll", this.boundHandleScroll, { passive: true })

    this.boundSaveBeforeVisit = this.saveAllState.bind(this)
    document.addEventListener("turbo:before-visit", this.boundSaveBeforeVisit)

    this.boundPreApply = this.preApplyState.bind(this)
    document.addEventListener("turbo:before-render", this.boundPreApply)

    this.boundToggleDetails = this.handleDetailsToggle.bind(this)
    this.element.addEventListener("toggle", this.boundToggleDetails, true)
  }

  disconnect() {
    this.saveAllState()

    this.element.removeEventListener("scroll", this.boundHandleScroll)
    document.removeEventListener("turbo:before-visit", this.boundSaveBeforeVisit)
    document.removeEventListener("turbo:before-render", this.boundPreApply)
    this.element.removeEventListener("toggle", this.boundToggleDetails, true)

    if (this.scrollTimeout) clearTimeout(this.scrollTimeout)
  }

  handleScroll() {
    if (this.scrollTimeout) clearTimeout(this.scrollTimeout)
    this.scrollTimeout = setTimeout(() => this.saveScrollPosition(), 100)
  }

  saveScrollPosition() {
    try {
      localStorage.setItem(this.storageKeyValue, this.element.scrollTop.toString())
    } catch (_) { /* quota exceeded or private browsing */ }
  }

  restoreScrollPosition() {
    const pending = this.element.dataset.pendingScroll
    if (pending !== undefined) {
      delete this.element.dataset.pendingScroll
      const pos = parseInt(pending, 10)
      if (!isNaN(pos) && pos >= 0) {
        this.element.scrollTop = pos
        return
      }
    }

    const saved = localStorage.getItem(this.storageKeyValue)
    if (saved !== null) {
      const pos = parseInt(saved, 10)
      if (!isNaN(pos) && pos >= 0) {
        this.element.scrollTop = pos
      }
    }
  }

  saveAllState() {
    this.saveScrollPosition()
    this.saveDetailsStates()
  }

  handleDetailsToggle(event) {
    const details = event.target
    if (details.tagName !== "DETAILS") return
    const id = details.dataset.detailsId
    if (!id) return
    try {
      if (details.open) {
        localStorage.setItem(`details_${id}_open`, "true")
      } else {
        localStorage.removeItem(`details_${id}_open`)
      }
    } catch (_) { /* quota exceeded */ }
  }

  saveDetailsStates() {
    this.element.querySelectorAll("details[data-details-id]").forEach(el => {
      const id = el.dataset.detailsId
      try {
        if (el.open) {
          localStorage.setItem(`details_${id}_open`, "true")
        } else {
          localStorage.removeItem(`details_${id}_open`)
        }
      } catch (_) { /* quota exceeded */ }
    })
  }

  restoreDetailsStates() {
    this.element.querySelectorAll("details[data-details-id]").forEach(el => {
      const id = el.dataset.detailsId
      if (localStorage.getItem(`details_${id}_open`) === "true") {
        el.open = true
      }
    })
  }

  /**
   * Pre-apply scroll position and dropdown states to the incoming body
   * before Turbo paints it, preventing the flash of default state.
   */
  preApplyState(event) {
    const newBody = event.detail?.newBody
    if (!newBody) return

    const scrollContainer = newBody.querySelector("[data-controller~='sidebar-scroll']")
    if (scrollContainer) {
      const saved = localStorage.getItem(this.storageKeyValue)
      if (saved !== null) {
        const pos = parseInt(saved, 10)
        if (!isNaN(pos) && pos > 0) {
          scrollContainer.dataset.pendingScroll = pos
        }
      }
    }

    this.preApplyDropdownStates(newBody)
    this.preApplyDetailsStates(newBody)
  }

  /**
   * Apply saved dropdown open/closed states to the new body's menu
   * elements before they are rendered, eliminating the collapse-then-expand flash.
   */
  preApplyDropdownStates(body) {
    const dropdowns = body.querySelectorAll("[data-controller~='guild-dropdown']")
    dropdowns.forEach(el => {
      const guildId = el.dataset.guildId
      if (!guildId) return

      const saved = localStorage.getItem(`dropdown_${guildId}_open`)
      if (saved === "true") {
        const menu = el.querySelector("[data-guild-dropdown-target='menu']")
        const icon = el.querySelector("[data-guild-dropdown-target='icon']")
        if (menu) menu.classList.remove("hidden")
        if (icon) icon.classList.add("rotate-180")
      }
    })
  }

  preApplyDetailsStates(body) {
    body.querySelectorAll("details[data-details-id]").forEach(el => {
      const id = el.dataset.detailsId
      if (localStorage.getItem(`details_${id}_open`) === "true") {
        el.open = true
      }
    })
  }
}
