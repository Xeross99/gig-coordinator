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

// Directional view-transition flag. Before Turbo fires the navigation (and the
// browser kicks off a view transition), we classify the jump based on the
// from/to paths and set `data-transition-direction` on <html>. CSS then picks
// different keyframes for "forward" (feed → event) and "back" (event → feed).
// Everything else falls back to the default fade.
const FEED_PATHS = new Set(["/", "/eventy"])
const isEventShow = (path) => /^\/eventy\/[^/]+$/.test(path)

document.addEventListener("turbo:visit", (event) => {
  const fromPath = window.location.pathname
  const toPath = new URL(event.detail.url, window.location.origin).pathname

  let direction = "fade"
  if (FEED_PATHS.has(fromPath) && isEventShow(toPath)) direction = "forward"
  else if (isEventShow(fromPath) && FEED_PATHS.has(toPath)) direction = "back"

  document.documentElement.dataset.transitionDirection = direction
})

document.addEventListener("turbo:load", () => {
  delete document.documentElement.dataset.transitionDirection
})
