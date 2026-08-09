import { Controller } from "@hotwired/stimulus"

// Modal „Wyjeżdżam" kierowcy: ustawianie kolejności odbierania pasażerów
// przez przeciąganie. Reorder na pointer events (HTML5 drag & drop nie
// działa na dotyku), elementy listy niosą hidden inputy pickup_order[],
// więc kolejność <li> w DOM jest wprost kolejnością submitowanych wartości.
export default class extends Controller {
  static targets = ["dialog", "list", "item"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  startDrag(event) {
    if (this.itemTargets.length < 2) return
    event.preventDefault()
    this.dragged = event.currentTarget
    this.dragged.setPointerCapture(event.pointerId)
    this.dragged.classList.add("opacity-70", "ring-2", "ring-sky-400", "bg-sky-50")
  }

  drag(event) {
    if (!this.dragged) return
    const y = event.clientY
    for (const item of this.itemTargets) {
      if (item === this.dragged) continue
      const rect = item.getBoundingClientRect()
      if (y < rect.top || y > rect.bottom) continue
      const ref = y < rect.top + rect.height / 2 ? item : item.nextElementSibling
      if (ref !== this.dragged && ref !== this.dragged.nextElementSibling) {
        this.listTarget.insertBefore(this.dragged, ref)
        this.renumber()
      }
      break
    }
  }

  endDrag() {
    if (!this.dragged) return
    this.dragged.classList.remove("opacity-70", "ring-2", "ring-sky-400", "bg-sky-50")
    this.dragged = null
  }

  renumber() {
    this.itemTargets.forEach((item, index) => {
      item.querySelector("[data-ordinal]").textContent = `${index + 1}.`
    })
  }
}
