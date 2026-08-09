import { Controller } from "@hotwired/stimulus"

// Skopiuj zawartość `source` do schowka i pokaż „Skopiowane!" przez 1.5s.
// `navigator.clipboard.writeText` dostępny na każdej współczesnej przeglądarce
// pod HTTPS (i pod localhost). Fallback: select() + execCommand jeśli API
// niedostępne (raczej nie wystąpi w tej apce, ale tańsze niż awaria).
export default class extends Controller {
  static targets = ["source", "label"]

  disconnect() {
    clearTimeout(this._timer)
  }

  async copy() {
    const text = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.sourceTarget.select()
      document.execCommand("copy")
    }
    this.flash("Skopiowane!")
  }

  flash(message) {
    if (!this.hasLabelTarget) return
    const original = this.labelTarget.textContent
    this.labelTarget.textContent = message
    clearTimeout(this._timer)
    this._timer = setTimeout(() => {
      this.labelTarget.textContent = original
    }, 1500)
  }
}
