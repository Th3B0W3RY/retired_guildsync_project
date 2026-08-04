// Entry point for the build script
import "@hotwired/turbo-rails"
import "./controllers"

// Trix + ActionText only on pages with a rich-text editor (admin/marketing forms).
// Read-only `.trix-content` on the landing page does not need editor JS; loading globally
// caused `element.dispatchEvent is not a function` on unrelated pages (e.g. members gear).
let actionTextLoadPromise = null

function pageHasRichTextEditor() {
  return document.querySelector("trix-editor") !== null
}

function loadActionTextIfNeeded() {
  if (!pageHasRichTextEditor()) return Promise.resolve()
  if (actionTextLoadPromise) return actionTextLoadPromise

  actionTextLoadPromise = Promise.all([
    import("trix"),
    import("@rails/actiontext")
  ]).catch((error) => {
    actionTextLoadPromise = null
    console.error("Failed to load Trix/ActionText:", error)
    throw error
  })

  return actionTextLoadPromise
}

function bootActionText() {
  loadActionTextIfNeeded()
}

document.addEventListener("DOMContentLoaded", bootActionText)
document.addEventListener("turbo:load", bootActionText)
