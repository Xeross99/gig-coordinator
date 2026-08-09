import { Controller } from "@hotwired/stimulus"

// Dynamically adds/removes sub-event rows in the campaign form. Wzorzec
// "cocoon-replacement bez gemów": template[data-nested-events-target=template]
// trzyma jeden pusty wiersz z child_index = NEW_RECORD; każde kliknięcie
// "Dodaj sub-event" klonuje template, podmienia NEW_RECORD na unikatowy
// timestamp i wstawia przed przyciskiem "+ Dodaj".
export default class extends Controller {
  static targets = ["template", "container"]

  connect() {
    // Pierwszy wiersz dodajemy automatycznie tylko na nowym formularzu (gdy
    // container jest pusty). Na edycji backend już renderuje wszystkie istniejące.
    if (this.hasContainerTarget && this.containerTarget.children.length === 0) {
      this.add()
    }
  }

  add(event) {
    if (event) event.preventDefault()
    if (!this.hasTemplateTarget || !this.hasContainerTarget) return

    const id = new Date().getTime()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, id)
    const wrapper = document.createElement("div")
    wrapper.innerHTML = html
    const row = wrapper.firstElementChild
    if (row) this.containerTarget.appendChild(row)
  }

  // Markuje wiersz do usunięcia przy zapisie. Jeśli persistent (ma `id`), ustawia
  // hidden _destroy=1 i ukrywa wiersz. Jeśli nowy (jeszcze nie zapisany), usuwa
  // z DOM żeby nie wysyłać go w POST.
  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-sub-event-row]")
    if (!row) return
    const persistedIdInput = row.querySelector('input[name*="[id]"]')
    if (persistedIdInput && persistedIdInput.value) {
      const destroyInput = row.querySelector('input[name*="[_destroy]"]')
      if (destroyInput) destroyInput.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }
}
