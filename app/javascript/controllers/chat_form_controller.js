import { Controller } from "@hotwired/stimulus"

// Submit wiadomości klawiszem Enter na desktopie + autofocus na edytor po
// re-renderze formularza (po wysłaniu lub błędzie walidacji), żeby user mógł
// od razu pisać dalej bez klikania.
export default class extends Controller {
  static values = { autofocus: Boolean }

  connect() {
    this.onKeydown = this.onKeydown.bind(this)
    // Capture phase — żeby przechwycić Enter ZANIM Lexical wstawi newline do
    // edytora. Wyjątek: gdy popover promptu (`.lexxy-prompt-menu--visible`)
    // jest otwarty — wtedy oddajemy Enter Lexxy'emu do wyboru podpowiedzi.
    this.element.addEventListener("keydown", this.onKeydown, { capture: true })

    if (this.autofocusValue) {
      // `requestAnimationFrame` daje Lexxy'emu chwilę na pełne zainicjowanie
      // po mount — bez tego .focus() bywa no-op na świeżo podmienionej ramce.
      const editor = this.element.querySelector("lexxy-editor")
      if (editor) requestAnimationFrame(() => editor.focus())
    }
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.onKeydown, { capture: true })
  }

  onKeydown(event) {
    if (event.key !== "Enter") return
    if (event.shiftKey || event.ctrlKey || event.metaKey) return
    if (event.isComposing) return
    // Mobile i tablety — zostawiamy Enter na newline (standard komunikatorów).
    if (window.matchMedia("(pointer: coarse)").matches) return
    // Prompt otwarty → Enter wybiera podpowiedź, nie submit. Klasa
    // `lexxy-prompt-menu--visible` doklejana jest tylko gdy dropdown
    // faktycznie jest widoczny (sam `.lexxy-prompt-menu` żyje w DOM-ie
    // też w stanie ukrytym).
    if (document.querySelector(".lexxy-prompt-menu--visible")) return

    event.preventDefault()
    event.stopPropagation()
    this.element.requestSubmit()
  }
}
