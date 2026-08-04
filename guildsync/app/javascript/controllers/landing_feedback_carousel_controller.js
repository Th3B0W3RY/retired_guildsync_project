import { Controller } from "@hotwired/stimulus"

/**
 * Guest landing: auto-advance rich-text feedback slides (interval from SiteSetting via data attribute),
 * pause on hover, focus on controls, arrow keys, swipe. Respects prefers-reduced-motion (no autoplay).
 *
 * Uses ResizeObserver on the slide viewport so translateX uses a real width after layout (avoids
 * Windows/Chrome timing where clientWidth was 0 on first paint). Focus on the region root (tabindex=0)
 * does not pause autoplay; focus inside interactive children does.
 */
export default class extends Controller {
  static targets = ["track", "slide", "live", "dot"]
  static values = {
    interval: { type: Number, default: 6000 },
    announceTemplate: { type: String, default: "User feedback %{current} of %{total}" },
  }

  connect() {
    this.index = 0
    this.slideCount = this.slideTargets.length
    this.paused = false
    this.timer = null
    this.touchStartX = null
    this.loopResetTimer = null
    this._resizeObserver = null
    this._viewportEl = null

    if (!this.hasSlideTarget || !this.hasTrackTarget || this.slideCount === 0) return

    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this._pause = () => this.pause()
    this._resume = () => this.resume()
    this._onFocusIn = (event) => this.onFocusIn(event)
    this._onFocusOut = (event) => this.onFocusOut(event)
    this._onKeydown = (e) => this.onKeydown(e)
    this._onVisibility = () => this.onVisibilityChange()

    if (this.slideCount > 1) {
      this.cloneSlide = this.slideTargets[0].cloneNode(true)
      this.cloneSlide.setAttribute("aria-hidden", "true")
      this.trackTarget.appendChild(this.cloneSlide)
    }

    this._viewportEl = this.trackTarget.parentElement
    if (this._viewportEl && typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(() => this.applyTransform())
      this._resizeObserver.observe(this._viewportEl)
    }

    this.applyTransform()
    if (!this.reducedMotion) {
      this.startTicker()
      this.element.addEventListener("mouseenter", this._pause)
      this.element.addEventListener("mouseleave", this._resume)
      this.element.addEventListener("focusin", this._onFocusIn)
      this.element.addEventListener("focusout", this._onFocusOut)
    }

    this.element.addEventListener("keydown", this._onKeydown)
    document.addEventListener("visibilitychange", this._onVisibility)

    this.boundTouchStart = (e) => {
      this.touchStartX = e.changedTouches[0]?.screenX
    }
    this.boundTouchEnd = (e) => {
      const endX = e.changedTouches[0]?.screenX
      if (this.touchStartX == null || endX == null) return
      const delta = endX - this.touchStartX
      if (Math.abs(delta) < 48) return
      if (delta > 0) this.step(-1)
      else this.step(1)
      this.touchStartX = null
    }
    this.trackTarget.addEventListener("touchstart", this.boundTouchStart, { passive: true })
    this.trackTarget.addEventListener("touchend", this.boundTouchEnd, { passive: true })

    this.boundResize = () => this.applyTransform()
    window.addEventListener("resize", this.boundResize)

    this.announceSlide()
    this.syncDots()

    requestAnimationFrame(() => {
      requestAnimationFrame(() => this.applyTransform())
    })
  }

  disconnect() {
    this.stopTicker()
    this.clearLoopReset()
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
      this._resizeObserver = null
    }
    this._viewportEl = null
    this.element.removeEventListener("mouseenter", this._pause)
    this.element.removeEventListener("mouseleave", this._resume)
    this.element.removeEventListener("focusin", this._onFocusIn)
    this.element.removeEventListener("focusout", this._onFocusOut)
    this.element.removeEventListener("keydown", this._onKeydown)
    document.removeEventListener("visibilitychange", this._onVisibility)
    if (this.trackTarget) {
      this.trackTarget.removeEventListener("touchstart", this.boundTouchStart)
      this.trackTarget.removeEventListener("touchend", this.boundTouchEnd)
    }
    window.removeEventListener("resize", this.boundResize)
    if (this.cloneSlide) {
      this.cloneSlide.remove()
      this.cloneSlide = null
    }
  }

  startTicker() {
    this.stopTicker()
    if (this.slideCount <= 1) return
    this.timer = window.setInterval(() => this.tick(), this.intervalValue)
  }

  stopTicker() {
    if (this.timer) {
      window.clearInterval(this.timer)
      this.timer = null
    }
  }

  tick() {
    if (this.paused || this.slideCount === 0) return
    if (this.slideCount === 1) return
    this.index += 1
    this.applyTransform()
    this.announceSlide()
    this.syncDots()

    if (this.index === this.slideCount) {
      this.scheduleLoopReset()
    }
  }

  step(delta) {
    if (this.slideCount === 0) return
    this.clearLoopReset()
    if (this.index === this.slideCount) {
      this.withoutTransition(() => {
        this.index = 0
        this.applyTransform()
      })
    }

    this.index = (this.index + delta + this.slideCount) % this.slideCount
    this.applyTransform()
    this.announceSlide()
    this.syncDots()
    if (!this.reducedMotion) {
      this.stopTicker()
      this.startTicker()
    }
  }

  previous() {
    this.step(-1)
  }

  next() {
    this.step(1)
  }

  goTo(event) {
    const nextIndex = Number.parseInt(event.currentTarget.dataset.index || "", 10)
    if (!Number.isInteger(nextIndex) || nextIndex < 0 || nextIndex >= this.slideCount) return
    this.clearLoopReset()
    this.index = nextIndex
    this.applyTransform()
    this.announceSlide()
    this.syncDots()
    if (!this.reducedMotion) {
      this.stopTicker()
      this.startTicker()
    }
  }

  slideWidth() {
    const inner = this.trackTarget?.parentElement
    const w = inner?.clientWidth
    if (w && w > 0) return w
    const rect = inner?.getBoundingClientRect?.()
    if (rect && rect.width > 0) return rect.width
    const first = this.slideTargets[0]
    const slideRect = first?.getBoundingClientRect?.()
    if (slideRect && slideRect.width > 0) return slideRect.width
    return first?.offsetWidth || 0
  }

  applyTransform() {
    if (!this.trackTarget || this.slideCount === 0) return
    const w = this.slideWidth()
    this.trackTarget.style.transform = `translateX(-${this.index * w}px)`
  }

  onKeydown(e) {
    if (e.key === "ArrowLeft") {
      e.preventDefault()
      this.step(-1)
    } else if (e.key === "ArrowRight") {
      e.preventDefault()
      this.step(1)
    }
  }

  announceSlide() {
    if (!this.hasLiveTarget) return
    const n = this.slideCount
    if (n === 0) return
    const activeIndex = this.index % n
    const progress = this.announceTemplateValue
      .replace("%{current}", String(activeIndex + 1))
      .replace("%{total}", String(n))
    const raw = this.slideTargets[activeIndex]?.innerText || ""
    const snippet = raw.replace(/\s+/g, " ").trim().slice(0, 140)
    this.liveTarget.textContent = snippet ? `${progress}. ${snippet}` : progress
  }

  pause() {
    this.paused = true
    this.stopTicker()
  }

  resume() {
    if (this.reducedMotion || document.hidden) return
    this.paused = false
    this.startTicker()
  }

  onVisibilityChange() {
    if (document.hidden) this.pause()
    else this.resume()
  }

  onFocusIn(event) {
    if (event.target === this.element) return
    this.pause()
  }

  onFocusOut(event) {
    const nextFocused = event.relatedTarget
    if (nextFocused && this.element.contains(nextFocused)) return
    this.resume()
  }

  scheduleLoopReset() {
    this.clearLoopReset()
    this.loopResetTimer = window.setTimeout(() => {
      this.withoutTransition(() => {
        this.index = 0
        this.applyTransform()
      })
      this.syncDots()
      this.loopResetTimer = null
    }, 820)
  }

  clearLoopReset() {
    if (!this.loopResetTimer) return
    window.clearTimeout(this.loopResetTimer)
    this.loopResetTimer = null
  }

  withoutTransition(work) {
    const previous = this.trackTarget.style.transition
    this.trackTarget.style.transition = "none"
    work()
    requestAnimationFrame(() => {
      this.trackTarget.style.transition = previous
    })
  }

  syncDots() {
    if (!this.hasDotTarget || this.slideCount === 0) return
    const activeIndex = this.index % this.slideCount
    this.dotTargets.forEach((dot, idx) => {
      const active = idx === activeIndex
      dot.classList.toggle("bg-[#615FFF]", active)
      dot.classList.toggle("scale-110", active)
      dot.classList.toggle("bg-[#4B5568]", !active)
      dot.setAttribute("aria-current", active ? "true" : "false")
    })
  }
}
