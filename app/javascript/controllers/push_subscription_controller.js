import { Controller } from "@hotwired/stimulus"

// <div data-controller="push-subscription"
//      data-push-subscription-vapid-public-key-value="<%= Rails.application.credentials.vapid.public_key %>"
//      data-push-subscription-endpoint-url-value="<%= push_subscriptions_path %>"
//      data-push-subscription-csrf-token-value="<%= form_authenticity_token %>">
// </div>
export default class extends Controller {
  static values = {
    vapidPublicKey: String,
    endpointUrl: String,
    csrfToken: String
  }

  connect() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) return
    if (Notification.permission === "denied") return

    this.#subscribe().catch((err) => console.warn("push subscribe failed", err))
  }

  async #subscribe() {
    const registration = await navigator.serviceWorker.register("/service-worker.js")
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
