import { Controller } from "@hotwired/stimulus"

const ICONS = {
  success: `<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
  </svg>`,
  error: `<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
  </svg>`,
  warning: `<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
    <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
  </svg>`,
  info: `<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
    <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
  </svg>`,
}

const STYLES = {
  success: "bg-green-900/95 border-green-700 text-green-100",
  error:
    "bg-red-950/95 border-2 border-red-500 text-red-50 ring-2 ring-red-500/40 shadow-lg shadow-red-950/50 font-medium",
  warning: "bg-yellow-900/95 border-yellow-700 text-yellow-100",
  info:    "bg-blue-900/95 border-blue-700 text-blue-100",
}

const FALLBACK_DEFAULT_MS = 2500

export default class extends Controller {
  static values = { defaultMs: Number }

  connect() {
    const fromValue = this.hasDefaultMsValue ? this.defaultMsValue : NaN
    this._defaultDuration =
      Number.isFinite(fromValue) && fromValue >= 0 ? fromValue : FALLBACK_DEFAULT_MS

    // Display flash toasts injected via data attributes from server-side
    this.element.querySelectorAll("[data-flash-type]").forEach((el) => {
      this.show(el.dataset.flashType, el.dataset.flashMessage)
      el.remove()
    })

    // Listen for programmatic toast events dispatched anywhere on the page
    this._handler = (e) => this.show(e.detail.type || "info", e.detail.message, e.detail.duration)
    window.addEventListener("toast:show", this._handler)
  }

  disconnect() {
    window.removeEventListener("toast:show", this._handler)
  }

  show(type, message, duration) {
    if (!message) return
    const safeType = ICONS[type] ? type : "info"
    const baseMs = duration ?? this._defaultDuration
    // Keep errors/permission denials readable slightly longer than success toasts.
    const ms =
      safeType === "error" ? Math.max(baseMs, 2800) : safeType === "warning" ? Math.max(baseMs, 2600) : baseMs

    const toast = document.createElement("div")
    toast.setAttribute("role", "alert")
    toast.className = [
      "flex items-start gap-3 w-full max-w-md",
      "px-4 py-3 rounded-lg border shadow-lg",
      "transition-all duration-300 opacity-100 translate-y-0",
      STYLES[safeType],
    ].join(" ")

    toast.innerHTML = `
      ${ICONS[safeType]}
      <span class="flex-1 text-sm leading-snug">${this._escape(message)}</span>
      <button type="button" class="shrink-0 opacity-70 hover:opacity-100 transition-opacity ml-1 -mt-0.5" aria-label="Dismiss">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
          <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
        </svg>
      </button>
    `

    toast.querySelector("button").addEventListener("click", () => this._dismiss(toast))
    this.element.appendChild(toast)

    // Trigger entry animation on next frame
    requestAnimationFrame(() => toast.classList.add("opacity-100"))

    if (ms > 0) {
      setTimeout(() => this._dismiss(toast), ms)
    }
  }

  _dismiss(toast) {
    toast.classList.add("opacity-0", "-translate-y-2")
    toast.addEventListener("transitionend", () => toast.remove(), { once: true })
  }

  _escape(str) {
    const d = document.createElement("div")
    d.textContent = str
    return d.innerHTML
  }
}
