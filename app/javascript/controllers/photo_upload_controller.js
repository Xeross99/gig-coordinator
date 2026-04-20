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
    if (this.hasSubmitTarget) this.submitTarget.disabled = true

    const upload = new DirectUpload(file, this.urlValue, this)

    upload.create((error, blob) => {
      if (error) {
        console.error("[DirectUpload]", error)
        this.statusTarget.textContent = "Błąd przesyłania"
        this.progressBarTarget.classList.remove("bg-stone-900")
        this.progressBarTarget.classList.add("bg-red-500")
        if (this.hasSubmitTarget) this.submitTarget.disabled = true
      } else {
        this.hiddenInputTarget.value = blob.signed_id
        this.hiddenInputTarget.disabled = false
        this.progressBarTarget.style.width = "100%"
        this.statusTarget.textContent = "Gotowe"
        if (this.hasSubmitTarget) this.submitTarget.disabled = false
      }
    })
  }

  directUploadWillStoreFileWithXHR(request) {
    request.upload.addEventListener("progress", event => {
      const progress = (event.loaded / event.total) * 100
      this.progressBarTarget.style.width = `${progress}%`
    })
  }
}
