import { Controller } from "@hotwired/stimulus"

// Drawer sidebar: mobile layout variant (application.html+mobile) and narrow desktop (application.html).
export default class extends Controller {
  static targets = ["backdrop", "panel"]

  connect() {
    this._onKeydown = (e) => {
      if (e.key === "Escape") this.close()
    }
    document.addEventListener("keydown", this._onKeydown)
    this._onTurboBeforeVisit = () => this.close()
    document.addEventListener("turbo:before-visit", this._onTurboBeforeVisit)
    this._desktopDrawerMedia = window.matchMedia("(min-width: 1024px)")
    this._onDesktopDrawerMediaChange = () => {
      if (this._desktopDrawerMedia.matches) this.close()
    }
    this._desktopDrawerMedia.addEventListener("change", this._onDesktopDrawerMediaChange)
    if (this.hasPanelTarget) {
      this._onPanelClick = (e) => {
        if (e.target.closest("a")) this.close()
      }
      this.panelTarget.addEventListener("click", this._onPanelClick)
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
    if (this._onTurboBeforeVisit) {
      document.removeEventListener("turbo:before-visit", this._onTurboBeforeVisit)
    }
    if (this._desktopDrawerMedia && this._onDesktopDrawerMediaChange) {
      this._desktopDrawerMedia.removeEventListener("change", this._onDesktopDrawerMediaChange)
    }
    if (this.hasPanelTarget && this._onPanelClick) {
      this.panelTarget.removeEventListener("click", this._onPanelClick)
    }
    document.body.classList.remove("overflow-hidden")
  }

  // Default layout uses #desktop-sidebar-panel + Tailwind lg:translate-x-0; at lg+ the drawer must not strip -translate-x-full
  // (needed when resizing back below lg). Mobile layout (#mobile-sidebar-panel) is always a drawer regardless of width.
  get _suppressDrawerOpenBecauseDesktopLayoutWide() {
    if (!this.hasPanelTarget || !this._desktopDrawerMedia) return false
    return (
      this.panelTarget.id === "desktop-sidebar-panel" &&
      this._desktopDrawerMedia.matches
    )
  }

  toggle() {
    if (this._suppressDrawerOpenBecauseDesktopLayoutWide) return
    if (this.isOpen()) this.close()
    else this.open()
  }

  open() {
    if (this._suppressDrawerOpenBecauseDesktopLayoutWide) return
    if (!this.hasBackdropTarget || !this.hasPanelTarget) return
    this.backdropTarget.classList.remove("hidden")
    this.panelTarget.classList.remove("-translate-x-full")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    if (!this.hasBackdropTarget || !this.hasPanelTarget) return
    this.backdropTarget.classList.add("hidden")
    this.panelTarget.classList.add("-translate-x-full")
    document.body.classList.remove("overflow-hidden")
  }

  isOpen() {
    if (!this.hasPanelTarget) return false
    if (this._suppressDrawerOpenBecauseDesktopLayoutWide) return false
    return !this.panelTarget.classList.contains("-translate-x-full")
  }
}
