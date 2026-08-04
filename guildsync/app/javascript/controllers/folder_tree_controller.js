import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    guildId: String
  }

  toggleFolder(event) {
    event.stopPropagation()
    const folderId = event.currentTarget.dataset.folderId
    const children = document.querySelector(`[data-folder-children="${folderId}"]`)
    const icon = document.querySelector(`[data-folder-icon="${folderId}"]`)
    
    if (children) {
      children.classList.toggle('hidden')
      if (icon) {
        icon.classList.toggle('rotate-90')
      }
    }
  }
}

