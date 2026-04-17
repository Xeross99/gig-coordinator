import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.dismiss(), 5000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.classList.add("opacity-0", "translate-y-2", "sm:translate-x-2", "sm:translate-y-0")
    setTimeout(() => this.element.remove(), 300)
  }
}
