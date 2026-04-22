import { Controller } from "@hotwired/stimulus"

// Pilnuje scrollowania czatu:
// 1. Na mount viewport jedzie na dół (najnowsze wiadomości).
// 2. Kiedy przyjdzie nowa wiadomość (append przez Turbo broadcast):
//    - jeśli user był blisko dołu → auto-scroll,
//    - w przeciwnym razie zostawiamy jego pozycję (czyta stare).
// 3. Kiedy user SAM wysyła wiadomość (submit formularza czatu) → zawsze scroll,
//    niezależnie od pozycji, bo oczekuje że zobaczy swój wpis natychmiast.
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

    // Śledzimy „był blisko dołu" NA BIEŻĄCO przez listener scrolla. Czytamy to
    // w MutationObserver — tam scrollHeight jest już powiększony o nową
    // wiadomość, więc `isNearBottom()` z wnętrza callbacku fałszywie mówi
    // „daleko od dołu" dla każdej wiadomości wyższej niż próg.
    this.wasNearBottom = true
    this.onScroll = () => { this.wasNearBottom = this.isNearBottom() }
    this.viewportTarget.addEventListener("scroll", this.onScroll, { passive: true })

    // Submit własnej wiadomości → ustaw flagę forsującą następny auto-scroll,
    // niezależnie od pozycji viewportu. Form dosadzany jest siblingiem (nie
    // dzieckiem viewportu), więc listener łapiemy na całej sekcji kontrolera.
    this.onSubmit = () => { this.forceNextScroll = true }
    this.element.addEventListener("submit", this.onSubmit, true)

    // Id listy to `chat_messages_event_<id>` (dom_id z prefiksem), więc
    // szukamy po PREFIKSIE. Poprzednio było `id$='_chat_messages'` (sufiks) —
    // ten selector nigdy nie matchował, przez co MutationObserver nie startował
    // i auto-scroll nie działał przy żadnym appendzie.
    const list = this.viewportTarget.querySelector("ul[id^='chat_messages_']")
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
      if (!isAppend) return

      if (this.forceNextScroll || this.wasNearBottom) {
        this.forceNextScroll = false
        this.scrollToBottom()
        // Po broadcast-append z websocketu wysokość potrafi jeszcze urosnąć
        // (obrazy ładują się async), więc strzelamy jeszcze w kolejnej klatce.
        requestAnimationFrame(() => this.scrollToBottom())
      }
    })
    this.mutationObserver.observe(list, { childList: true })
  }

  disconnect() {
    this.mutationObserver?.disconnect()
    this.viewportTarget?.removeEventListener("scroll", this.onScroll)
    this.element.removeEventListener("submit", this.onSubmit, true)
  }

  isNearBottom() {
    const v = this.viewportTarget
    return v.scrollHeight - v.scrollTop - v.clientHeight < 120
  }

  scrollToBottom() {
    this.viewportTarget.scrollTop = this.viewportTarget.scrollHeight
  }
}
