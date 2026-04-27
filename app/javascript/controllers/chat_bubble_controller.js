import { Controller } from "@hotwired/stimulus"

// Wyrównuje „moje" wiadomości w czacie po prawej stronie + zmienia kolor bąbelka.
// Działa klientowo, bo broadcast Turbo Stream leci tym samym HTML-em do wszystkich
// subskrybentów — nie możemy decydować po `Current.user` server-side.
//
// Markup: `<ul data-controller="chat-bubble" data-chat-bubble-current-user-id-value="42">`
// z dziećmi `<li class="message-row" data-user-id="…">`.
//
// Nowe wiadomości doklejane przez Turbo Stream (after_create_commit) trafiają do
// listy jako mutacje DOM — MutationObserver łapie je i też oznaczamy.
export default class extends Controller {
  static values = { currentUserId: String }

  connect() {
    this.markAll()
    this.observer = new MutationObserver((mutations) => {
      for (const m of mutations) {
        m.addedNodes.forEach((node) => {
          if (node.nodeType === 1) this.markRow(node)
        })
      }
    })
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  markAll() {
    this.element.querySelectorAll(".message-row").forEach((row) => this.markRow(row))
  }

  markRow(row) {
    if (!row.classList?.contains("message-row")) return
    const me = this.currentUserIdValue
    if (!me) return
    if (row.dataset.userId !== me) return

    row.classList.add("flex-row-reverse")
    row.querySelector(".message-avatar")?.classList.add("hidden")
    const body = row.querySelector(".message-body")
    body?.classList.add("flex", "flex-col", "items-end")
    row.querySelector(".message-meta")?.classList.add("flex-row-reverse")
    row.querySelector(".message-author")?.classList.add("hidden")

    // Bąbelek zostaje w tej samej palecie co u innych — tylko zmieniamy
    // zaokrąglenie po stronie autora (lewy „ogon" → prawy).
    const bubble = row.querySelector(".message-bubble")
    if (bubble) {
      bubble.classList.remove("rounded-tl-md")
      bubble.classList.add("rounded-tr-md")
    }
  }
}
