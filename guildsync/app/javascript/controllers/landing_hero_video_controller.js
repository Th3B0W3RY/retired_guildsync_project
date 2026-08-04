import { Controller } from "@hotwired/stimulus"

// Seamless hero loop (community pattern: dual <video> + opacity crossfade, no native loop).
// Native loop often hitches when seeking to 0; we fade to a second layer that starts near 0.
// Pairs with hero-background.mp4 (FFmpeg tail→head xfade) per README_HERO_VIDEO.md.
// playbackRate 0.75. rAF refines timeupdate (~4 Hz); requestVideoFrameCallback before fade when available.
const PLAYBACK_RATE = 0.75
const CROSSFADE_LEAD_SEC = 1.25
const CROSSFADE_CLEANUP_MS = 1200
const INCOMING_START_SEC = 0.04

export default class extends Controller {
  static targets = ["media", "dimOverlay"]

  connect() {
    this.boundVisibility = this.onVisibilityChange.bind(this)
    this.boundTurboBeforeCache = this.onTurboBeforeCache.bind(this)
    this.boundPageShow = this.onPageShow.bind(this)
    this.boundStalled = () => this.scheduleTryPlay(200)
    this.boundWaiting = () => this.scheduleTryPlay(150)
    this.boundLoadedMeta = () => this.tryPlay()
    this.boundLoadedData = () => this.tryPlay()
    this.boundCanPlay = () => this.tryPlay()
    this.boundTimeUpdate = (e) => this.onTimeUpdate(e.target)
    this.boundEnded = (e) => this.onMediaEnded(e.target)
    this.boundEndedLoop = () => this.onEndedLoop()
    this.retryTimers = []
    this.watchdogId = null
    this.crossfadeEndTimer = null
    this.crossfadeScheduled = false
    this.activeIndex = 0
    this.preciseRafId = null

    document.addEventListener("visibilitychange", this.boundVisibility)
    document.addEventListener("turbo:before-cache", this.boundTurboBeforeCache)
    window.addEventListener("pageshow", this.boundPageShow)

    this.mediaTargets.forEach((v) => {
      v.addEventListener("stalled", this.boundStalled)
      v.addEventListener("waiting", this.boundWaiting)
      v.addEventListener("loadedmetadata", this.boundLoadedMeta)
      v.addEventListener("loadeddata", this.boundLoadedData)
      v.addEventListener("canplay", this.boundCanPlay)
      if (this.dualLayer) {
        v.addEventListener("timeupdate", this.boundTimeUpdate)
        v.addEventListener("ended", this.boundEnded)
      } else {
        v.addEventListener("ended", this.boundEndedLoop)
      }
    })

    this.setupIntersectionObserver()
    this.startWatchdog()
    this.scheduleInitialRetries()
  }

  disconnect() {
    this.stopPreciseBoundaryCheck()
    this.clearCrossfadeTimer()
    this.clearRetryTimers()
    this.stopWatchdog()
    this.clearDimOverlay()
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
    document.removeEventListener("visibilitychange", this.boundVisibility)
    document.removeEventListener("turbo:before-cache", this.boundTurboBeforeCache)
    window.removeEventListener("pageshow", this.boundPageShow)

    this.mediaTargets.forEach((v) => {
      v.removeEventListener("stalled", this.boundStalled)
      v.removeEventListener("waiting", this.boundWaiting)
      v.removeEventListener("loadedmetadata", this.boundLoadedMeta)
      v.removeEventListener("loadeddata", this.boundLoadedData)
      v.removeEventListener("canplay", this.boundCanPlay)
      v.removeEventListener("timeupdate", this.boundTimeUpdate)
      v.removeEventListener("ended", this.boundEnded)
      v.removeEventListener("ended", this.boundEndedLoop)
    })
  }

  get dualLayer() {
    return this.mediaTargets.length >= 2
  }

  activeVideo() {
    return this.mediaTargets[this.activeIndex]
  }

  setDimOverlayActive(on) {
    if (!this.hasDimOverlayTarget) return
    this.dimOverlayTarget.classList.toggle("landing-hero-crossfade-dim", on)
  }

  clearDimOverlay() {
    this.setDimOverlayActive(false)
  }

  stopPreciseBoundaryCheck() {
    if (this.preciseRafId != null) {
      cancelAnimationFrame(this.preciseRafId)
      this.preciseRafId = null
    }
  }

  shouldSkipPlayback() {
    return false
  }

  onVisibilityChange() {
    if (document.visibilityState === "visible") this.scheduleTryPlay(0)
  }

  onTurboBeforeCache() {
    this.stopPreciseBoundaryCheck()
    this.clearDimOverlay()
    this.mediaTargets.forEach((v) => {
      try {
        v.pause()
      } catch (_) {
        /* ignore */
      }
    })
  }

  onPageShow(event) {
    if (!event.persisted) return
    this.stopPreciseBoundaryCheck()
    this.clearCrossfadeTimer()
    this.clearDimOverlay()
    this.crossfadeScheduled = false
    this.activeIndex = 0
    this.mediaTargets.forEach((v) => {
      v.muted = true
      v.defaultMuted = true
      try {
        v.load()
      } catch (_) {
        /* ignore */
      }
    })
    if (this.dualLayer) this.resetDualLayerClasses()
    this.scheduleInitialRetries()
  }

  resetDualLayerClasses() {
    const [a, b] = this.mediaTargets
    a.classList.remove("opacity-0", "z-[1]")
    a.classList.add("opacity-100", "z-[2]")
    a.style.zIndex = ""
    b.classList.remove("opacity-100", "z-[2]")
    b.classList.add("opacity-0", "z-[1]")
    b.style.zIndex = ""
  }

  onTimeUpdate(video) {
    if (!this.dualLayer || this.crossfadeScheduled) return
    if (video !== this.activeVideo()) return
    const dur = video.duration
    if (!Number.isFinite(dur) || dur <= 0) return
    const remaining = dur - video.currentTime
    if (remaining <= CROSSFADE_LEAD_SEC) {
      this.startCrossfade()
      return
    }
    if (remaining <= CROSSFADE_LEAD_SEC * 2) this.armPreciseBoundaryCheck()
  }

  armPreciseBoundaryCheck() {
    if (!this.dualLayer || this.crossfadeScheduled || this.preciseRafId != null) return
    const tick = () => {
      this.preciseRafId = null
      if (!this.dualLayer || this.crossfadeScheduled) return
      const v = this.activeVideo()
      if (!v || v.paused) return
      const dur = v.duration
      if (!Number.isFinite(dur) || dur <= 0) return
      const remaining = dur - v.currentTime
      if (remaining <= CROSSFADE_LEAD_SEC) {
        this.startCrossfade()
        return
      }
      if (remaining <= CROSSFADE_LEAD_SEC * 2) {
        this.preciseRafId = requestAnimationFrame(tick)
      }
    }
    this.preciseRafId = requestAnimationFrame(tick)
  }

  onMediaEnded(video) {
    if (!this.dualLayer) return
    if (video !== this.activeVideo()) return
    if (this.crossfadeScheduled) return
    this.startCrossfade()
  }

  /** Single-video fallback */
  onEndedLoop() {
    if (!this.hasMediaTarget) return
    if (this.shouldSkipPlayback()) return
    const v = this.mediaTarget
    if (v.loop && v.currentTime < 0.15) {
      this.applyPlaybackRate()
      this.tryPlay()
      return
    }
    try {
      v.currentTime = 0
    } catch (_) {
      /* ignore */
    }
    this.applyPlaybackRate()
    this.tryPlay()
  }

  scheduleOpacitySwap(incoming, runSwap) {
    let done = false
    const swap = () => {
      if (done) return
      done = true
      requestAnimationFrame(runSwap)
    }
    const t = window.setTimeout(() => swap(), 280)

    if (typeof incoming.requestVideoFrameCallback === "function") {
      incoming.requestVideoFrameCallback(() => {
        clearTimeout(t)
        swap()
      })
      return
    }

    if (!incoming.paused && incoming.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      clearTimeout(t)
      swap()
      return
    }

    incoming.addEventListener(
      "playing",
      () => {
        clearTimeout(t)
        swap()
      },
      { once: true }
    )
  }

  startCrossfade() {
    if (!this.dualLayer || this.crossfadeScheduled) return
    const outgoing = this.mediaTargets[this.activeIndex]
    const incoming = this.mediaTargets[1 - this.activeIndex]
    if (!outgoing || !incoming) return

    this.stopPreciseBoundaryCheck()
    this.crossfadeScheduled = true
    this.setDimOverlayActive(true)

    try {
      outgoing.pause()
    } catch (_) {
      /* ignore */
    }

    incoming.style.zIndex = "3"
    try {
      incoming.currentTime = INCOMING_START_SEC
    } catch (_) {
      /* ignore */
    }
    this.applyPlaybackRateTo(incoming)

    const runOpacitySwap = () => {
      outgoing.classList.remove("opacity-100", "z-[2]")
      outgoing.classList.add("opacity-0", "z-[1]")
      incoming.classList.remove("opacity-0", "z-[1]")
      incoming.classList.add("opacity-100", "z-[2]")
    }

    const p = incoming.play()
    if (p !== undefined && typeof p.then === "function") {
      p.then(() => this.scheduleOpacitySwap(incoming, runOpacitySwap)).catch(() => {
        this.scheduleOpacitySwap(incoming, runOpacitySwap)
      })
    } else {
      this.scheduleOpacitySwap(incoming, runOpacitySwap)
    }

    this.clearCrossfadeTimer()
    this.crossfadeEndTimer = window.setTimeout(() => {
      this.crossfadeEndTimer = null
      try {
        outgoing.pause()
        outgoing.currentTime = INCOMING_START_SEC
      } catch (_) {
        /* ignore */
      }
      outgoing.style.zIndex = ""
      incoming.style.zIndex = ""
      this.activeIndex = 1 - this.activeIndex
      this.crossfadeScheduled = false
      this.clearDimOverlay()
    }, CROSSFADE_CLEANUP_MS)
  }

  clearCrossfadeTimer() {
    if (this.crossfadeEndTimer != null) {
      clearTimeout(this.crossfadeEndTimer)
      this.crossfadeEndTimer = null
    }
  }

  applyPlaybackRate() {
    if (!this.hasMediaTarget) return
    this.mediaTargets.forEach((v) => this.applyPlaybackRateTo(v))
  }

  applyPlaybackRateTo(v) {
    try {
      v.playbackRate = PLAYBACK_RATE
    } catch (_) {
      /* ignore */
    }
  }

  setupIntersectionObserver() {
    if (typeof IntersectionObserver === "undefined") return
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) this.scheduleTryPlay(0)
        })
      },
      { root: null, rootMargin: "0px", threshold: 0.01 }
    )
    this.observer.observe(this.element)
  }

  startWatchdog() {
    this.stopWatchdog()
    this.watchdogId = window.setInterval(() => {
      if (!this.hasMediaTarget) return
      if (this.shouldSkipPlayback()) return
      let v
      if (this.dualLayer && this.crossfadeScheduled) {
        v = this.mediaTargets[1 - this.activeIndex]
      } else if (this.dualLayer) {
        v = this.activeVideo()
      } else {
        v = this.mediaTarget
      }
      if (!v) return
      if (v.paused && v.readyState >= HTMLMediaElement.HAVE_METADATA) {
        this.tryPlay()
      }
    }, 2000)
  }

  stopWatchdog() {
    if (this.watchdogId != null) {
      clearInterval(this.watchdogId)
      this.watchdogId = null
    }
  }

  clearRetryTimers() {
    this.retryTimers.forEach((id) => clearTimeout(id))
    this.retryTimers = []
  }

  scheduleInitialRetries() {
    this.clearRetryTimers()
    ;[0, 50, 100, 200, 400, 800, 1600, 3200].forEach((ms) => {
      this.retryTimers.push(window.setTimeout(() => this.tryPlay(), ms))
    })
  }

  scheduleTryPlay(ms) {
    this.retryTimers.push(window.setTimeout(() => this.tryPlay(), ms))
  }

  tryPlay() {
    if (!this.hasMediaTarget) return
    if (this.shouldSkipPlayback()) return

    if (this.dualLayer) {
      this.mediaTargets.forEach((v) => {
        v.muted = true
        v.defaultMuted = true
        try {
          v.playsInline = true
        } catch (_) {
          /* ignore */
        }
        v.setAttribute("playsinline", "")
        v.setAttribute("webkit-playsinline", "")
        this.applyPlaybackRateTo(v)
      })
      if (this.crossfadeScheduled) {
        const incoming = this.mediaTargets[1 - this.activeIndex]
        const playPromise = incoming.play()
        if (playPromise !== undefined && typeof playPromise.then === "function") {
          playPromise.catch(() => {
            /* Autoplay policy */
          })
        }
        return
      }
      this.mediaTargets.forEach((v, i) => {
        if (i !== this.activeIndex) {
          try {
            v.pause()
            v.currentTime = INCOMING_START_SEC
          } catch (_) {
            /* ignore */
          }
        }
      })
      const playPromise = this.activeVideo().play()
      if (playPromise !== undefined && typeof playPromise.then === "function") {
        playPromise.catch(() => {
          /* Autoplay policy; watchdog will retry */
        })
      }
      return
    }

    const v = this.mediaTarget
    v.muted = true
    v.defaultMuted = true
    try {
      v.playsInline = true
    } catch (_) {
      /* ignore */
    }
    v.setAttribute("playsinline", "")
    v.setAttribute("webkit-playsinline", "")

    this.applyPlaybackRateTo(v)

    const playPromise = v.play()
    if (playPromise !== undefined && typeof playPromise.then === "function") {
      playPromise.catch(() => {
        /* Autoplay policy; watchdog will retry */
      })
    }
  }
}
