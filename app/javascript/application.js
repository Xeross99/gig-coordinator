// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"
import "@tailwindplus/elements"

// Custom <turbo-stream action="visit" target="/path"> — used to push a
// server-side navigation over a Turbo Stream (e.g. send an invited user
// straight to the event they were just reserved on).
Turbo.StreamActions.visit = function() {
  const url = this.getAttribute("target")
  if (url) Turbo.visit(url)
}

// Directional view-transition flag. Before Turbo fires the navigation (and
// the browser kicks off a view transition), we classify the jump by nav depth
// and set `data-transition-direction` on <html>. CSS picks different keyframes
// for "forward" (going deeper, e.g. feed → event → history) and "back" (going
// shallower). Everything else falls back to the default fade.
//   depth 0: feed (/, /eventy)
//   depth 1: event show (/eventy/:slug)
//   depth 2: event history (/eventy/:slug/historia)
function navDepth(path) {
  if (path === "/" || path === "/eventy") return 0
  if (/^\/eventy\/[^/]+\/historia$/.test(path)) return 2
  if (/^\/eventy\/[^/]+$/.test(path)) return 1
  return null
}

document.addEventListener("turbo:visit", (event) => {
  const fromPath = window.location.pathname
  const toPath   = new URL(event.detail.url, window.location.origin).pathname
  const from = navDepth(fromPath)
  const to   = navDepth(toPath)

  let direction = "fade"
  if (from !== null && to !== null && from !== to) {
    direction = to > from ? "forward" : "back"
  }

  document.documentElement.dataset.transitionDirection = direction
})

document.addEventListener("turbo:load", () => {
  delete document.documentElement.dataset.transitionDirection
})

// Register the service worker as early as possible — even for anonymous
// visitors on /logowanie — so the SWR cache starts populating on the very
// first visit. push_subscription_controller also calls register() when a
// signed-in user mounts, but register() is idempotent, so there's no clash.
// The SW itself (app/views/pwa/service-worker.js) handles stale-while-revalidate
// HTML caching + cache-first asset caching, making cold-starts feel instant.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker").catch((err) => {
      console.warn("service worker register failed", err)
    })
  })
}
