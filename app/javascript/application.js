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
