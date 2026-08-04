import { Controller } from "@hotwired/stimulus"

const VOTE_ON_SM = "vote-btn rounded px-2 py-1 text-sm font-medium bg-theme-brand-gradient text-white"
const VOTE_OFF_SM = "vote-btn rounded px-2 py-1 text-sm font-medium bg-[rgba(29,41,61,0.5)] text-[#90A1B9] hover:text-white"
const VOTE_ON_LG = "vote-btn rounded px-4 py-2 text-sm font-medium bg-theme-brand-gradient text-white"
const VOTE_OFF_LG = "vote-btn rounded px-4 py-2 text-sm font-medium bg-[rgba(29,41,61,0.5)] text-[#90A1B9] hover:text-white"

export default class extends Controller {
  static targets = ["modal", "form", "submitBtn", "createError", "column", "tab", "createStatus"]
  static values = { activeTab: { type: String, default: "considering" } }

  connect() {
    this._onResize = () => {
      this.applyColumnLayout()
      this.syncTabs()
    }
    window.addEventListener("resize", this._onResize)
    this.applyColumnLayout()
    this.syncTabs()
    if (this.hasFormTarget) {
      this._onCreateSubmitStart = () => {
        if (this.hasSubmitBtnTarget) this.submitBtnTarget.disabled = true
      }
      this._onCreateSubmitEnd = (event) => {
        if (this.hasSubmitBtnTarget) this.submitBtnTarget.disabled = false
        if (!event.detail.success) return
        const ct = event.detail.fetchResponse?.response?.headers?.get("Content-Type") || ""
        if (!ct.includes("turbo-stream")) return
        this.closeModal()
        if (this.hasFormTarget) this.formTarget.reset()
        if (this.hasCreateErrorTarget) this.createErrorTarget.innerHTML = ""
      }
      this.formTarget.addEventListener("turbo:submit-start", this._onCreateSubmitStart)
      this.formTarget.addEventListener("turbo:submit-end", this._onCreateSubmitEnd)
    }
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
    if (this.hasFormTarget) {
      if (this._onCreateSubmitStart) {
        this.formTarget.removeEventListener("turbo:submit-start", this._onCreateSubmitStart)
      }
      if (this._onCreateSubmitEnd) {
        this.formTarget.removeEventListener("turbo:submit-end", this._onCreateSubmitEnd)
      }
    }
  }

  showTab(event) {
    const status = event.params.status
    if (!status) return
    this.activeTabValue = status
  }

  activeTabValueChanged() {
    this.applyColumnLayout()
    this.syncTabs()
  }

  applyColumnLayout() {
    if (!this.hasColumnTarget) return
    const wide = window.matchMedia("(min-width: 1024px)").matches
    this.columnTargets.forEach((el) => {
      if (wide) {
        el.classList.remove("hidden")
      } else {
        const on = el.dataset.status === this.activeTabValue
        el.classList.toggle("hidden", !on)
      }
    })
  }

  syncTabs() {
    if (!this.hasTabTarget) return
    this.tabTargets.forEach((btn) => {
      const on = btn.dataset.status === this.activeTabValue
      btn.setAttribute("aria-selected", on ? "true" : "false")
      btn.classList.toggle("border-[#7C86FF]", on)
      btn.classList.toggle("text-white", on)
      btn.classList.toggle("border-transparent", !on)
      btn.classList.toggle("text-[#90A1B9]", !on)
    })
  }

  openModal() {
    if (this.hasCreateErrorTarget) this.createErrorTarget.innerHTML = ""
    if (this.hasCreateStatusTarget) this.createStatusTarget.innerHTML = ""
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      this.modalTarget.classList.add("flex")
    }
  }

  closeModal() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      this.modalTarget.classList.remove("flex")
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  vote(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    const id = btn.dataset.roadmapIdParam
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!id || !token) return
    btn.disabled = true
    fetch(`/roadmap/requests/${id}/vote`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    })
      .then((r) => r.json())
      .then((data) => {
        const countEl = btn.querySelector(".vote-count")
        if (countEl) countEl.textContent = data.vote_count
        const lg = btn.dataset.roadmapSizeParam === "lg"
        btn.className = data.voted ? (lg ? VOTE_ON_LG : VOTE_ON_SM) : (lg ? VOTE_OFF_LG : VOTE_OFF_SM)
      })
      .catch(() => window.showToast('error', "Could not update vote. Please try again."))
      .finally(() => { btn.disabled = false })
  }
}
