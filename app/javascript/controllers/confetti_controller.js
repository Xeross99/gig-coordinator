import { Controller } from "@hotwired/stimulus"
import confetti from "canvas-confetti"

export default class extends Controller {
  connect() {
    const defaults = { startVelocity: 28, spread: 65, ticks: 160, scalar: 0.8, zIndex: 1000, disableForReducedMotion: true }
    const end = Date.now() + 550

    const frame = () => {
      confetti({ ...defaults, particleCount: 5, origin: { x: 0, y: 0.33 }, angle: 60  })
      confetti({ ...defaults, particleCount: 5, origin: { x: 1, y: 0.33 }, angle: 120 })
      if (Date.now() < end) requestAnimationFrame(frame)
    }
    frame()

    this.element.remove()
  }
}
