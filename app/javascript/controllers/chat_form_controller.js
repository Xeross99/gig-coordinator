import { Controller } from "@hotwired/stimulus"

// Submit wiadomości klawiszem Enter na desktopie + autofocus na edytor po
// re-renderze formularza (po błędzie walidacji), żeby user mógł od razu
// pisać dalej bez klikania. Na sukces NIE podmieniamy DOM-u — czyścimy
// `editor.value` po stronie klienta, żeby na iOS klawiatura została
// otwarta (replace formularza chowa keyboard, bo focus znika z
// `<lexxy-editor>` na chwilę DOM swap).
export default class extends Controller {
  static values = { autofocus: Boolean }

  connect() {
    this.onKeydown   = this.onKeydown.bind(this)
    this.onSubmitEnd = this.onSubmitEnd.bind(this)
    // Capture phase — żeby przechwycić Enter ZANIM Lexical wstawi newline do
    // edytora. Wyjątek: gdy popover promptu (`.lexxy-prompt-menu--visible`)
    // jest otwarty — wtedy oddajemy Enter Lexxy'emu do wyboru podpowiedzi.
    this.element.addEventListener("keydown", this.onKeydown, { capture: true })
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)

    if (this.autofocusValue) {
      // `requestAnimationFrame` daje Lexxy'emu chwilę na pełne zainicjowanie
      // po mount — bez tego .focus() bywa no-op na świeżo podmienionej ramce.
      const editor = this.element.querySelector("lexxy-editor")
      if (editor) requestAnimationFrame(() => editor.focus())
    }
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.onKeydown, { capture: true })
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  onSubmitEnd(event) {
    if (!event.detail?.success) return
    // Server zwraca 204 No Content na sukces — DOM formularza nie jest
    // wymieniany, więc tylko czyścimy edytor lokalnie. `set value` w lexxy
    // robi `root.selectEnd()`, więc focus zostaje na contenteditable
    // i klawiatura na iOS nie znika.
    const editor = this.element.querySelector("lexxy-editor")
    if (!editor) return
    editor.value = ""
    editor.focus()
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
