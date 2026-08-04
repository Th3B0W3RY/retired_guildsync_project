import { Controller } from "@hotwired/stimulus"
import { devWarn, devError } from "../helpers/dev_console"

/**
 * Global monthly/annual toggle for pricing grids (upgrade, billing, public pricing).
 * Runs on every Turbo visit via Stimulus connect() — avoids DOMContentLoaded-only bugs.
 */
export default class extends Controller {
  static values = {
    checkoutPath: { type: String, default: "/billing/create_checkout_session" },
    planChangePath: { type: String, default: "" },
    previewPlanPath: { type: String, default: "" },
    loadingText: String,
    priceMissingText: String,
    checkoutFailedText: String,
    confirmPlanChangeText: String,
    confirmPlanChangeWithAmountText: String,
    planChangeFailedText: { type: String, default: "Unable to change plan." }
  }

  static targets = ["intervalToggle", "intervalThumb", "planCard"]

  connect() {
    this.isAnnual = false
    this.abortController = new AbortController()
    const { signal } = this.abortController

    if (this.hasIntervalToggleTarget) {
      this.intervalToggleTarget.addEventListener("click", () => this.toggleGlobal(), { signal })
    }

    this.applyGlobalPricing()
    if (this.hasIntervalToggleTarget) {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => this.syncIntervalThumbPosition())
      })
    }

    this.planCardTargets.forEach((card) => {
      const btn = card.querySelector(".checkout-btn, .billing-checkout-btn, .billing-plan-change-btn, .public-checkout-btn")
      if (btn) this.bindPlanAction(btn, signal)
    })
  }

  disconnect() {
    this.abortController.abort()
  }

  toggleGlobal() {
    this.isAnnual = !this.isAnnual
    this.applyGlobalPricing()
  }

  applyGlobalPricing() {
    this.planCardTargets.forEach((card) => this.applyCardInterval(card))

    if (this.hasIntervalToggleTarget && this.hasIntervalThumbTarget) {
      const toggle = this.intervalToggleTarget
      toggle.setAttribute("data-interval", this.isAnnual ? "year" : "month")
      toggle.setAttribute("aria-checked", this.isAnnual ? "true" : "false")
      this.syncIntervalThumbPosition()
    }
  }

  /** Measured slide — works for /pricing (padded track) and upgrade/billing (border-2) toggles. */
  syncIntervalThumbPosition() {
    if (!this.hasIntervalToggleTarget || !this.hasIntervalThumbTarget) return
    const toggle = this.intervalToggleTarget
    const thumb = this.intervalThumbTarget
    ;["translate-x-0", "translate-x-0.5", "translate-x-1", "translate-x-7", "translate-x-8"].forEach((c) => {
      thumb.classList.remove(c)
    })
    const cs = getComputedStyle(toggle)
    const pl = parseFloat(cs.paddingLeft) || 0
    const pr = parseFloat(cs.paddingRight) || 0
    const inner = toggle.clientWidth - pl - pr
    const knobW = thumb.offsetWidth || 24
    const delta = Math.max(0, inner - knobW)
    const offset = this.isAnnual ? delta : 0
    thumb.style.transform = `translate3d(${offset}px,0,0)`
  }

  applyCardInterval(card) {
    const wrap = card.querySelector(".upgrade-price-wrap, .billing-price-wrap, .pricing-price-wrap")
    if (!wrap) return

    const priceMonthly = wrap.querySelector(".price-monthly, .billing-price-monthly")
    const priceAnnual = wrap.querySelector(".price-annual, .billing-price-annual")
    const btn = card.querySelector(".checkout-btn, .billing-checkout-btn, .billing-plan-change-btn, .public-checkout-btn")

    if (priceMonthly) priceMonthly.classList.toggle("hidden", this.isAnnual)
    if (priceAnnual) priceAnnual.classList.toggle("hidden", !this.isAnnual)

    if (btn) {
      const monthlyId = btn.getAttribute("data-price-monthly")
      const annualId = btn.getAttribute("data-price-annual")
      const id = this.isAnnual && annualId ? annualId : monthlyId
      btn.setAttribute("data-current-price", id || "")
    }
  }

  bindPlanAction(button, signal) {
    button.addEventListener("click", () => this.onPlanButtonClick(button), { signal })
  }

  onPlanButtonClick(button) {
    const planId = button.getAttribute("data-plan-id")
    if (this.hasPlanChangePathValue && this.planChangePathValue && planId) {
      this.startPlanChange(button, planId)
    } else {
      this.startCheckout(button)
    }
  }

  startCheckout(button) {
    const priceId = button.getAttribute("data-current-price") || button.getAttribute("data-price-monthly")
    if (!priceId) {
      window.showToast?.("error", this.priceMissingTextValue)
      return
    }

    button.disabled = true
    const originalText = button.textContent
    button.textContent = this.loadingTextValue

    const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""

    fetch(this.checkoutPathValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf,
        Accept: "application/json"
      },
      body: JSON.stringify({ price_id: priceId })
    })
      .then((r) => {
        if (!r.ok) return r.json().then((d) => { throw new Error(d.error || "Failed") })
        return r.json()
      })
      .then((data) => {
        if (data.url) window.location.href = data.url
        else throw new Error("No URL")
      })
      .catch((err) => {
        devError(err)
        window.showToast?.("error", err.message || this.checkoutFailedTextValue)
        button.disabled = false
        button.textContent = originalText
      })
  }

  async startPlanChange(button, planId) {
    const interval = this.isAnnual ? "year" : "month"
    const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""

    let confirmMessage = this.confirmPlanChangeTextValue || "Change to this plan?"

    if (this.hasPreviewPlanPathValue && this.previewPlanPathValue) {
      try {
        const previewUrl = `${this.previewPlanPathValue}?plan_id=${encodeURIComponent(planId)}&interval=${encodeURIComponent(interval)}`
        const res = await fetch(previewUrl, { headers: { Accept: "application/json" } })
        if (res.ok) {
          const data = await res.json()
          if (data.formatted != null && data.formatted !== "" && this.confirmPlanChangeWithAmountTextValue) {
            confirmMessage = `${this.confirmPlanChangeWithAmountTextValue} ${data.formatted}?`
          }
        }
      } catch (e) {
        devWarn("Plan preview failed", e)
      }
    }

    if (!window.confirm(confirmMessage)) return

    button.disabled = true
    const originalText = button.textContent
    button.textContent = this.loadingTextValue

    try {
      const res = await fetch(this.planChangePathValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrf,
          Accept: "application/json"
        },
        body: JSON.stringify({ plan_id: planId, interval })
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) throw new Error(data.error || this.planChangeFailedTextValue)
      if (data.redirect_url) window.location.href = data.redirect_url
      else window.location.reload()
    } catch (err) {
      devError(err)
      window.showToast?.("error", err.message || this.planChangeFailedTextValue)
      button.disabled = false
      button.textContent = originalText
    }
  }
}
