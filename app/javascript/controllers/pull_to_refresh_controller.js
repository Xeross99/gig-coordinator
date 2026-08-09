import { Controller } from "@hotwired/stimulus"

// Pull-to-refresh for iOS PWA standalone mode (where the native gesture isn't
// available). Listens for touchstart at scrollTop 0, tracks vertical drag with
// some resistance, shows a centered indicator that scales + rotates based on
// pull distance, and triggers a full page reload once the threshold is
// crossed on release.
//
// Attach to body; expects `indicator` (outer pill) + `spinner` (arrow svg)
// targets somewhere inside.
export default class extends Controller {
  static targets = [ "indicator", "spinner" ]
  static values  = { threshold: { type: Number, default: 70 } }

  connect() {
    this.startY   = null
    this.distance = 0
    this.active   = false

    this.onStart = this.start.bind(this)
    this.onMove  = this.move.bind(this)
    this.onEnd   = this.end.bind(this)
    this.onLoad  = this.finishRefresh.bind(this)

    document.addEventListener("touchstart", this.onStart, { passive: true })
    document.addEventListener("touchmove",  this.onMove,  { passive: false })
    document.addEventListener("touchend",   this.onEnd,   { passive: true })
    document.addEventListener("touchcancel",this.onEnd,   { passive: true })
    // data-turbo-permanent keeps the indicator element (and this controller
    // instance) alive across Turbo.visit, so connect() won't re-fire after
    // navigation. We listen to turbo:load ourselves to fade the spinner out
    // once the fresh page is in place.
    document.addEventListener("turbo:load", this.onLoad)
  }

  disconnect() {
    document.removeEventListener("touchstart", this.onStart)
    document.removeEventListener("touchmove",  this.onMove)
    document.removeEventListener("touchend",   this.onEnd)
    document.removeEventListener("touchcancel",this.onEnd)
    document.removeEventListener("turbo:load", this.onLoad)
  }

  // Runs after Turbo swaps in the next page. If we were mid-refresh, give the
  // user one rotation's worth of visible spinner, then smoothly fade + slide
  // the indicator back up out of view.
  finishRefresh() {
    if (!this.indicatorTarget.classList.contains("refreshing")) return
    this.indicatorTarget.classList.remove("refreshing")
    this.indicatorTarget.style.transition = "transform 300ms cubic-bezier(0.22, 1, 0.36, 1), opacity 250ms ease-out"
    this.indicatorTarget.style.transform  = "translate(-50%, -40px) scale(0.5)"
    this.indicatorTarget.style.opacity    = "0"
    if (this.hasSpinnerTarget) this.spinnerTarget.style.transform = "rotate(0deg)"
    this.distance = 0
  }

  start(event) {
    if (event.touches.length !== 1) return
    if (window.scrollY > 0) return
    this.startY   = event.touches[0].clientY
    this.active   = true
    this.distance = 0
    // Drop transition while the finger is driving the motion.
    this.indicatorTarget.style.transition = "none"
    if (this.hasSpinnerTarget) this.spinnerTarget.style.transition = "none"
  }

  move(event) {
    if (!this.active || this.startY === null) return

    const y        = event.touches[0].clientY
    const rawDelta = y - this.startY

    if (rawDelta <= 0) { this.cancel(); return }

    // Damping: fast at first, tapers past the threshold.
    const max      = this.thresholdValue * 2
    const eased    = max * (1 - Math.exp(-rawDelta / (this.thresholdValue * 1.5)))
    this.distance  = eased

    if (event.cancelable) event.preventDefault()
    this.paint()
  }

  end() {
    if (!this.active) return
    const triggered = this.distance >= this.thresholdValue
    this.active = false
    this.startY = null

    if (triggered) {
      // Smooth snap back to the resting pose. We animate the indicator's
      // transform (250ms ease-out) so the release feels nice, but the spinner
      // itself drops its transition immediately — clearing its inline
      // rotation while a transition is live would race the CSS keyframe
      // (pull-spin) that's about to take over via the `.refreshing` class.
      this.distance = this.thresholdValue
      const y = this.thresholdValue - 20
      this.indicatorTarget.style.transition = "transform 250ms cubic-bezier(0.22, 1, 0.36, 1), opacity 200ms ease-out"
      this.indicatorTarget.style.transform  = `translate(-50%, ${y}px) scale(1)`
      this.indicatorTarget.style.opacity    = "1"
      this.indicatorTarget.classList.add("refreshing")
      if (this.hasSpinnerTarget) {
        this.spinnerTarget.style.transition = "none"
        this.spinnerTarget.style.transform  = ""
      }

      // Skip the view-transition for this specific navigation. View-transitions
      // freeze the real DOM for the duration of the snapshot, which would
      // interrupt the snap-back animation mid-flight.
      document.documentElement.dataset.transitionDirection = "none"

      // Wait for the snap-back to finish before kicking off Turbo.visit —
      // otherwise the view-transition snapshot lands mid-animation and
      // either freezes it or jumps the indicator. One-shot transitionend,
      // with a 350ms safety timeout in case the event never fires (reduced
      // motion, element off-screen, etc.).
      const startNav = () => {
        if (window.Turbo) {
          window.Turbo.visit(window.location.href, { action: "replace" })
        } else {
          window.location.reload()
        }
      }
      let fired = false
      const onDone = () => {
        if (fired) return
        fired = true
        this.indicatorTarget.removeEventListener("transitionend", onDone)
        startNav()
      }
      this.indicatorTarget.addEventListener("transitionend", onDone, { once: true })
      setTimeout(onDone, 350)
    } else {
      // Didn't pull past threshold — re-enable transitions so the indicator
      // glides back up instead of jumping.
      this.indicatorTarget.style.transition = "transform 250ms cubic-bezier(0.22, 1, 0.36, 1), opacity 200ms ease-out"
      if (this.hasSpinnerTarget) this.spinnerTarget.style.transition = "transform 250ms cubic-bezier(0.22, 1, 0.36, 1)"
      this.reset()
    }
  }

  cancel() {
    this.active = false
    this.startY = null
    this.indicatorTarget.style.transition = "transform 250ms cubic-bezier(0.22, 1, 0.36, 1), opacity 200ms ease-out"
    if (this.hasSpinnerTarget) this.spinnerTarget.style.transition = "transform 250ms cubic-bezier(0.22, 1, 0.36, 1)"
    this.reset()
  }

  paint() {
    const progress = Math.min(this.distance / this.thresholdValue, 1)
    const scale    = 0.5 + progress * 0.5    // 0.5 → 1.0
    const y        = this.distance - 20       // arrives from off-screen top
    const opacity  = Math.min(progress * 1.5, 1)

    this.indicatorTarget.style.transform = `translate(-50%, ${y}px) scale(${scale})`
    this.indicatorTarget.style.opacity   = opacity

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.style.transform = `rotate(${progress * 180}deg)`
    }

    this.indicatorTarget.classList.toggle("ready", this.distance >= this.thresholdValue)
  }

  reset() {
    this.distance = 0
    this.indicatorTarget.style.transform = "translate(-50%, -40px) scale(0.5)"
    this.indicatorTarget.style.opacity   = "0"
    this.indicatorTarget.classList.remove("ready", "refreshing")
    if (this.hasSpinnerTarget) this.spinnerTarget.style.transform = "rotate(0deg)"
  }
}
