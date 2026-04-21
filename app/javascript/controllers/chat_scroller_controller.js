import { Controller } from "@hotwired/stimulus"

// Pilnuje scrollowania czatu:
// 1. Na mount viewport jedzie na dół (najnowsze wiadomości).
// 2. Przy dodaniu wiadomości (append z Turbo broadcast) auto-scroll jeżeli
//    user jest już blisko dołu — inaczej zachowujemy jego pozycję, żeby nie
//    podrzucać widoku gdy czyta stare wiadomości.
export default class extends Controller {
  static targets = ["viewport"]

  connect() {
    // Wielofazowy scroll-to-bottom: avatary ładują się async, co zmienia
    // wysokość listy i „podrzuca" scroll. Strzelamy kilka razy + po każdym
    // `img.load` — gwarantuje że user zawsze startuje na najnowszej wiadomości.
    this.scrollToBottom()
    requestAnimationFrame(() => this.scrollToBottom())
    requestAnimationFrame(() => requestAnimationFrame(() => this.scrollToBottom()))
    this.viewportTarget.querySelectorAll("img").forEach((img) => {
      if (img.complete) return
      img.addEventListener("load",  () => this.scrollToBottom(), { once: true })
      img.addEventListener("error", () => this.scrollToBottom(), { once: true })
    })

    const list = this.viewportTarget.querySelector("ul[id$='_chat_messages']")
    if (!list) return

    this.mutationObserver = new MutationObserver((mutations) => {
      // Tylko `append` (nowa wiadomość na dole) interesuje nas tu — prepend
      // (infinite scroll w górę) przychodzi z `chat_load_more`, który sam
      // przywraca scrollTop. Detekcja: jeśli ostatni dodany node jest też
      // ostatnim dzieckiem listy, to był append; w przypadku prepend
      // dodane nody siedzą NA POCZĄTKU, więc lastAdded != list.lastChild.
      const added = mutations.flatMap((m) => Array.from(m.addedNodes))
                             .filter((n) => n.nodeType === 1)
      const lastAdded = added[added.length - 1]
      const isAppend  = lastAdded && lastAdded === list.lastElementChild
      if (isAppend && this.isNearBottom()) this.scrollToBottom()
    })
    this.mutationObserver.observe(list, { childList: true })
  }

  disconnect() {
    this.mutationObserver?.disconnect()
  }

  isNearBottom() {
    const v = this.viewportTarget
    return v.scrollHeight - v.scrollTop - v.clientHeight < 120
  }

  scrollToBottom() {
    this.viewportTarget.scrollTop = this.viewportTarget.scrollHeight
  }
}
