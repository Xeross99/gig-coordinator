import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { webcal: String, google: String }

  add() {
    if (/android/i.test(navigator.userAgent)) {
      window.open(this.googleValue, "_blank", "noopener")
    } else {
      window.location.href = this.webcalValue
    }
  }
}
