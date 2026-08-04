import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["folderSelect"]
  static values = {
    guildId: String
  }

  async move() {
    const folderId = this.folderSelectTarget.value
    const storageController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller*="storage"]'),
      'storage'
    )
    
    if (!storageController) return
    
    const selectedFiles = storageController.getSelectedFiles()
    if (selectedFiles.length === 0) {
      window.showToast('warning', 'Please select files to move')
      return
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) {
      window.showToast('error', 'Security token missing. Please refresh the page and try again.')
      return
    }

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/file_entries/bulk_move`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({
          file_ids: selectedFiles,
          folder_id: folderId || null
        })
      })

      const data = await response.json()
      
      if (data.success) {
        storageController.hideMoveModal()
        storageController.clearSelection()
        location.reload()
      } else {
        window.showToast('error', 'Error moving files: ' + (data.error || 'Unknown error'))
      }
    } catch (error) {
      console.error('Error:', error)
      window.showToast('error', 'Error moving files. Please try again.')
    }
  }
}

