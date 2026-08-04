import { Application } from "@hotwired/stimulus"
import { isDevHost } from "../helpers/dev_console"

const application = Application.start()

const isDev = isDevHost()

// Only enable debug and global reference in development
if (isDev) {
  application.debug = true
  window.Stimulus = application
}

// Log controllers after a brief delay to ensure all registrations are complete
setTimeout(() => {
  if (isDev) {
    console.log("Stimulus started (development mode)")
    console.log("Available controllers:", Object.keys(application.controllers))
  }
}, 100)

export { application }

// Global helper so any JS (inline scripts, legacy controllers) can show a toast
// without needing a direct Stimulus reference.
// Usage: window.showToast("error", "Something went wrong.")
//        window.showToast("success", "Done!", 3000)
window.showToast = function (type, message, duration) {
  window.dispatchEvent(new CustomEvent("toast:show", { detail: { type, message, duration } }))
}
