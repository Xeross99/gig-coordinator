import { Controller } from "@hotwired/stimulus"

// Replaces the browser's native `confirm()` with a `<el-dialog>` modal —
// driven by `data-turbo-confirm` on forms / links. See
// `app/views/shared/_turbo_confirm.html.erb` for the markup.
export default class extends Controller {
  static targets = [ "dialog", "message", "confirmButton" ]

  connect() {
    Turbo.config.forms.confirm = this.turboConfirm.bind(this)
  }

  turboConfirm(message, element, submitter) {
    if (!this.hasDialogTarget) {
      return Promise.resolve(confirm(message))
    }

    this.messageTarget.textContent = message

    if (submitter?.dataset.turboConfirmButton) {
      this.confirmButtonTarget.textContent = submitter.dataset.turboConfirmButton
    }

    this.dialogTarget.showModal()

    return new Promise((resolve) => {
      this.resolve = resolve
    })
  }

  onClose() {
    this.resolve?.(this.dialogTarget.returnValue === "confirm")
    this.dialogTarget.returnValue = ""
    this.resolve = null
  }

  confirm() {
    this.dialogTarget.returnValue = "confirm"
    this.dialogTarget.close()
  }

  cancel() {
    this.dialogTarget.returnValue = "cancel"
    this.dialogTarget.close()
  }
}
