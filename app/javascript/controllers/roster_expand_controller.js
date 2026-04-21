import { Controller } from "@hotwired/stimulus"

// Rozwija/zwija dodatkowych pracowników w sekcji „Wszyscy". Używa triku
// `grid-template-rows: 0fr → 1fr` + `transition` — płynnie animuje od 0 do
// naturalnej wysokości bez konieczności mierzenia treści w JS.
export default class extends Controller {
  static targets = ["collapsible", "button"]
  static values  = { count: Number }

  toggle() {
    const expanded = this.collapsibleTarget.classList.toggle("expanded")
    this.buttonTarget.textContent = expanded
      ? "Zwiń"
      : `Pokaż wszystkich (${this.countValue})`
  }
}
