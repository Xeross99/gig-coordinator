import { Controller } from "@hotwired/stimulus"

// Renders a 5-digit OTP as separate visual cells while keeping the interactive
// surface a single <input> with autocomplete="one-time-code". This is the most
// reliable pattern for iOS Safari OTP autofill — one input, one autocomplete
// attribute, no focus-juggling. Stimulus just mirrors the value into the
// visual cells on every input event and auto-submits when the 5th digit lands.
export default class extends Controller {
  static targets = ["input", "char", "cell"]

  connect() {
    requestAnimationFrame(() => this.inputTarget.focus())
    this.render()
  }

  update() {
    this.render()
    if (this.digits.length === 5) {
      this.element.closest("form")?.requestSubmit()
    }
  }

  render() {
    const digits = this.digits
    if (this.inputTarget.value !== digits) this.inputTarget.value = digits
    this.charTargets.forEach((el, i) => { el.textContent = digits[i] || "" })
    this.cellTargets.forEach((cell, i) => {
      const active = i === digits.length
      cell.classList.toggle("ring-2", active)
      cell.classList.toggle("ring-stone-900", active)
      cell.classList.toggle("ring-1", !active)
      cell.classList.toggle("ring-stone-300", !active)
    })
  }

  get digits() {
    return this.inputTarget.value.replace(/\D/g, "").slice(0, 5)
  }
}
