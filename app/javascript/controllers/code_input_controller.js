import { Controller } from "@hotwired/stimulus"

// Manages a 5-digit one-time code input split across separate <input> boxes.
// On submit, digits are joined into the hidden "merged" target so the server
// receives a single params[:code] = "12345".
export default class extends Controller {
  static targets = ["digit", "merged", "form"]

  connect() {
    this.element.addEventListener("submit", this.merge)
    // focus first empty digit on load
    requestAnimationFrame(() => {
      const first = this.digitTargets.find(d => !d.value) || this.digitTargets[0]
      first?.focus()
    })
  }

  disconnect() {
    this.element.removeEventListener("submit", this.merge)
  }

  input(event) {
    const input = event.target
    // Keep only digits, max 1 char
    const digits = input.value.replace(/\D/g, "")
    input.value = digits.slice(-1)
    if (digits.length >= 1) {
      const idx = this.digitTargets.indexOf(input)
      const next = this.digitTargets[idx + 1]
      if (next) next.focus()
    }
    if (digits.length > 1) {
      // user typed/pasted multiple digits into a single box — distribute
      this.distribute(digits)
    }
    if (this.isComplete) this.submit()
  }

  keydown(event) {
    if (event.key === "Backspace") {
      const input = event.target
      if (!input.value) {
        const idx = this.digitTargets.indexOf(input)
        const prev = this.digitTargets[idx - 1]
        if (prev) {
          prev.focus()
          prev.value = ""
          event.preventDefault()
        }
      }
    } else if (event.key === "ArrowLeft") {
      const idx = this.digitTargets.indexOf(event.target)
      this.digitTargets[idx - 1]?.focus()
    } else if (event.key === "ArrowRight") {
      const idx = this.digitTargets.indexOf(event.target)
      this.digitTargets[idx + 1]?.focus()
    }
  }

  paste(event) {
    const text = (event.clipboardData || window.clipboardData).getData("text")
    const digits = text.replace(/\D/g, "")
    if (digits.length) {
      event.preventDefault()
      this.distribute(digits)
      if (this.isComplete) this.submit()
    }
  }

  distribute(digits) {
    const chars = digits.slice(0, this.digitTargets.length).split("")
    this.digitTargets.forEach((el, i) => {
      el.value = chars[i] || ""
    })
    const firstEmpty = this.digitTargets.find(el => !el.value)
    if (firstEmpty) firstEmpty.focus()
    else this.digitTargets[this.digitTargets.length - 1].focus()
  }

  get isComplete() {
    return this.digitTargets.every(el => el.value.length === 1)
  }

  merge = () => {
    const value = this.digitTargets.map(el => el.value || "").join("")
    if (this.hasMergedTarget) this.mergedTarget.value = value
  }

  submit() {
    this.merge()
    if (this.element.tagName === "FORM") this.element.requestSubmit()
  }
}
