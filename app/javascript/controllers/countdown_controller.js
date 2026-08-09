import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { deadline: String }

  connect() {
    this.update()
    this.timer = setInterval(() => this.update(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  update() {
    const remainingMs = new Date(this.deadlineValue) - new Date()
    if (remainingMs <= 0) {
      this.element.textContent = "0sek"
      clearInterval(this.timer)
      return
    }
    const totalSec = Math.floor(remainingMs / 1000)
    const hours = Math.floor(totalSec / 3600)
    const minutes = Math.floor((totalSec % 3600) / 60)
    const seconds = totalSec % 60
    const parts = []
    if (hours > 0) parts.push(`${hours}h`)
    if (hours > 0 || minutes > 0) parts.push(`${minutes}min`)
    parts.push(`${seconds}sek`)
    this.element.textContent = parts.join(" ")
  }
}
