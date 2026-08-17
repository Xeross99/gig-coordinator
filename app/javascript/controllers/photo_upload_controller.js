import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["input", "hiddenInput", "progress", "progressBar", "filename", "status", "submit"]
  static values = { url: String }

  selectFile() {
    this.inputTarget.click()
  }

  upload() {
    const file = this.inputTarget.files[0]
    if (!file) return

    this.filenameTarget.textContent = file.name
    this.progressTarget.classList.remove("hidden")
    this.statusTarget.textContent = ""
    this.progressBarTarget.classList.remove("bg-red-500")
    this.progressBarTarget.classList.add("bg-stone-900")
    this.progressBarTarget.style.width = "0%"
    this.lockSubmit()

    const upload = new DirectUpload(file, this.urlValue, this)

    upload.create((error, blob) => {
      if (error) {
        console.error("[DirectUpload]", error)
        this.statusTarget.textContent = "Błąd przesyłania"
        this.progressBarTarget.classList.remove("bg-stone-900")
        this.progressBarTarget.classList.add("bg-red-500")
        this.lockSubmit()
      } else {
        this.hiddenInputTarget.value = blob.signed_id
        this.hiddenInputTarget.disabled = false
        this.progressBarTarget.style.width = "100%"
        this.statusTarget.textContent = "Gotowe"
        this.unlockSubmit()
      }
    })
  }

  // `data-static-disabled` wypisuje przycisk z globalnego progress-bar
  // fallbacku w `animations.css` — dopóki czeka na zdjęcie, `disabled` to
  // stan produktowy, nie ładowanie. Po odblokowaniu atrybut znika, żeby
  // realny submit dostał pasek postępu jak wszędzie indziej.
  lockSubmit() {
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = true
    this.submitTarget.setAttribute("data-static-disabled", "")
  }

  unlockSubmit() {
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = false
    this.submitTarget.removeAttribute("data-static-disabled")
  }

  directUploadWillStoreFileWithXHR(request) {
    request.upload.addEventListener("progress", event => {
      const progress = (event.loaded / event.total) * 100
      this.progressBarTarget.style.width = `${progress}%`
    })
  }
}
