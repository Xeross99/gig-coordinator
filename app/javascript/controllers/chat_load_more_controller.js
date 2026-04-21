import { Controller } from "@hotwired/stimulus"

// Infinite-scroll w górę dla czatu. Observer widzi gdy sentinel wchodzi w
// viewport → fetchuje `?before=<oldest_id>` (turbo_stream), renderuje
// prepend, potem restore'uje scrollTop żeby widok nie podskoczył.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.loading = false
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) this.load()
      },
      { root: this.viewport(), threshold: 0 }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  async load() {
    if (this.loading) return
    this.loading = true
    this.observer?.disconnect()

    const viewport   = this.viewport()
    const prevHeight = viewport ? viewport.scrollHeight : 0
    const prevTop    = viewport ? viewport.scrollTop    : 0

    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" }
      })
      if (!res.ok) return
      const html = await res.text()
      window.Turbo.renderStreamMessage(html)

      if (viewport) {
        requestAnimationFrame(() => {
          viewport.scrollTop = viewport.scrollHeight - prevHeight + prevTop
        })
      }
    } finally {
      this.loading = false
    }
  }

  viewport() {
    return this.element.closest("[data-chat-scroller-target='viewport']")
  }
}
