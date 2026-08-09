import { Controller } from "@hotwired/stimulus"

// Renders the push-subscription element. Two usage modes:
// 1) Hidden div in the layout — connect() auto-subscribes silently. Works on
//    Android/Chrome. iOS/Safari ignores requestPermission() outside a user
//    gesture, so connect() is a no-op there.
// 2) Profile card with button + status targets — `enable` action fires
//    requestPermission() from a real click, which iOS accepts.
//
// <div data-controller="push-subscription"
//      data-push-subscription-vapid-public-key-value="..."
//      data-push-subscription-endpoint-url-value="..."
//      data-push-subscription-csrf-token-value="...">
//   <button data-push-subscription-target="enable"
//           data-action="click->push-subscription#enable">Włącz</button>
//   <p data-push-subscription-target="status"></p>
// </div>
export default class extends Controller {
  static values = {
    vapidPublicKey: String,
    endpointUrl: String,
    csrfToken: String
  }

  static targets = ["enable", "status", "unsupported", "denied", "granted"]

  connect() {
    if (!this.#supported()) {
      this.#renderState("unsupported")
      return
    }

    this.#renderState(this.#permissionState())

    if (Notification.permission === "denied") return
    // Auto-subscribe on Android/Chrome; iOS no-ops silently.
    this.#subscribe().catch((err) => console.warn("push subscribe failed", err))
  }

  async enable(event) {
    event?.preventDefault?.()
    if (!this.#supported()) {
      this.#renderState("unsupported")
      return
    }
    if (Notification.permission === "denied") {
      this.#renderState("denied")
      return
    }
    try {
      await this.#subscribe()
    } catch (err) {
      console.warn("push subscribe failed", err)
    }
    this.#renderState(this.#permissionState())
  }

  #supported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  #permissionState() {
    return Notification.permission // "default" | "granted" | "denied"
  }

  #renderState(state) {
    // Inline style.display bije każdą Tailwindową utility — bez tego np.
    // `class="hidden inline-flex"` zawsze pokazuje element, bo `.inline-flex`
    // jest w skompilowanym CSS po `.hidden` i wygrywa source-orderem.
    const map = {
      unsupported: this.hasUnsupportedTarget ? this.unsupportedTarget : null,
      denied:      this.hasDeniedTarget      ? this.deniedTarget      : null,
      granted:     this.hasGrantedTarget     ? this.grantedTarget     : null,
      default:     this.hasEnableTarget      ? this.enableTarget      : null
    }
    Object.entries(map).forEach(([key, el]) => {
      if (!el) return
      el.style.display = (key === state) ? "" : "none"
    })
  }

  async #subscribe() {
    const registration = await navigator.serviceWorker.register("/service-worker")
    await navigator.serviceWorker.ready

    if (Notification.permission === "default") {
      const granted = await Notification.requestPermission()
      if (granted !== "granted") return
    } else if (Notification.permission !== "granted") {
      return
    }

    const existing = await registration.pushManager.getSubscription()
    const sub = existing ?? await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.#urlB64ToUint8Array(this.vapidPublicKeyValue)
    })

    await fetch(this.endpointUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfTokenValue },
      body: JSON.stringify({
        push_subscription: {
          endpoint:   sub.endpoint,
          p256dh_key: this.#keyToB64(sub.getKey("p256dh")),
          auth_key:   this.#keyToB64(sub.getKey("auth"))
        }
      })
    })
  }

  #urlB64ToUint8Array(b64) {
    const padding = "=".repeat((4 - b64.length % 4) % 4)
    const base64 = (b64 + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(base64)
    return Uint8Array.from([...raw].map(c => c.charCodeAt(0)))
  }

  #keyToB64(buffer) {
    return btoa(String.fromCharCode(...new Uint8Array(buffer)))
  }
}
