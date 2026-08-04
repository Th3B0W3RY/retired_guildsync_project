import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    guildId: String,
    canManage: Boolean
  }

  showCreateFolderModal() {
    const modal = document.getElementById('create-folder-modal')
    const input = document.getElementById('folder-name-input')
    if (modal) {
      modal.classList.remove('hidden')
      // DO NOT prevent body scrolling - we want to see the page behind
    }
    if (input) {
      input.value = ''
      input.focus()
    }
  }

  hideCreateFolderModal(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
      event.stopImmediatePropagation()
    }
    const modal = document.getElementById('create-folder-modal')
    if (modal) {
      modal.classList.add('hidden')
    }
  }

  hideCreateFolderModalOnOverlay(event) {
    // Only close if clicking directly on the overlay, not on the modal content
    if (event && event.target && event.target.id === 'create-folder-modal') {
      this.hideCreateFolderModal(event)
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  showMoveModal() {
    const selectedFiles = this.getSelectedFiles()
    if (selectedFiles.length === 0) {
      window.showToast('warning', 'Please select files to move')
      return
    }
    document.getElementById('move-modal').classList.remove('hidden')
  }

  hideMoveModal() {
    document.getElementById('move-modal').classList.add('hidden')
  }

  showDeleteModal(message, onConfirm) {
    document.getElementById('delete-message').textContent = message
    const confirmBtn = document.getElementById('confirm-delete-btn')
    confirmBtn.onclick = onConfirm
    document.getElementById('delete-modal').classList.remove('hidden')
  }

  hideDeleteModal() {
    document.getElementById('delete-modal').classList.add('hidden')
  }

  deleteFolder(event) {
    event.stopPropagation()
    const folderId = event.currentTarget.dataset.folderId
    const folderName = event.currentTarget.dataset.folderName
    
    this.showDeleteModal(
      `Are you sure you want to delete the folder "${folderName}"? This will also delete all files and subfolders inside it.`,
      () => {
        this.performFolderDelete(folderId)
      }
    )
  }

  async performFolderDelete(folderId) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) {
      window.showToast('error', 'Security token missing. Please refresh the page and try again.')
      return
    }

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/folders/${folderId}`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken,
          'Accept': 'application/json'
        },
        body: JSON.stringify({ confirm_delete: true })
      })

      const data = await response.json()
      
      if (data.success) {
        this.hideDeleteModal()
        location.reload() // Reload to refresh the view
      } else {
        window.showToast('error', 'Error deleting folder: ' + (data.error || 'Unknown error'))
        this.hideDeleteModal()
      }
    } catch (error) {
      console.error('Error:', error)
      window.showToast('error', 'Error deleting folder. Please try again.')
      this.hideDeleteModal()
    }
  }

  toggleSelectionMode() {
    const checkboxes = document.querySelectorAll('.file-checkbox')
    const isVisible = checkboxes[0]?.classList.contains('hidden')
    
    checkboxes.forEach(checkbox => {
      if (isVisible) {
        checkbox.classList.remove('hidden')
      } else {
        checkbox.classList.add('hidden')
        checkbox.checked = false
      }
    })
    
    this.updateBulkActionsBar()
  }

  clearSelection() {
    document.querySelectorAll('.file-checkbox').forEach(checkbox => {
      checkbox.checked = false
      checkbox.classList.add('hidden')
    })
    this.updateBulkActionsBar()
  }

  getSelectedFiles() {
    return Array.from(document.querySelectorAll('.file-checkbox:checked'))
      .map(checkbox => checkbox.dataset.fileId)
  }

  updateBulkActionsBar() {
    const selectedCount = this.getSelectedFiles().length
    const bulkBar = document.getElementById('bulk-actions-bar')
    
    if (selectedCount > 0) {
      document.getElementById('selected-count').textContent = `${selectedCount} file${selectedCount === 1 ? '' : 's'} selected`
      bulkBar.classList.remove('hidden')
    } else {
      bulkBar.classList.add('hidden')
    }
  }

  bulkDelete() {
    const selectedFiles = this.getSelectedFiles()
    if (selectedFiles.length === 0) return

    this.showDeleteModal(
      `Are you sure you want to delete ${selectedFiles.length} file${selectedFiles.length === 1 ? '' : 's'}?`,
      () => {
        this.performBulkDelete(selectedFiles)
      }
    )
  }

  async performBulkDelete(fileIds) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) {
      window.showToast('error', 'Security token missing. Please refresh the page and try again.')
      return
    }
    
    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/file_entries/bulk_destroy`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ file_ids: fileIds })
      })

      const data = await response.json()
      
      if (data.success) {
        fileIds.forEach(id => {
          const fileItem = document.querySelector(`[data-file-id="${id}"]`)
          if (fileItem) fileItem.remove()
        })
        this.clearSelection()
        location.reload() // Reload to refresh the view
      } else {
        window.showToast('error', 'Error deleting files: ' + (data.error || 'Unknown error'))
      }
    } catch (error) {
      console.error('Error:', error)
      window.showToast('error', 'Error deleting files. Please try again.')
    }
    
    this.hideDeleteModal()
  }

  async performDelete(fileId) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) {
      window.showToast('error', 'Security token missing. Please refresh the page and try again.')
      return
    }
    
    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/file_entries/${fileId}`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        }
      })

      const data = await response.json()
      
      if (data.success) {
        const fileItem = document.querySelector(`[data-file-id="${fileId}"]`)
        if (fileItem) fileItem.remove()
        location.reload() // Reload to refresh the view
      } else {
        window.showToast('error', 'Error deleting file: ' + (data.error || 'Unknown error'))
      }
    } catch (error) {
      console.error('Error:', error)
      window.showToast('error', 'Error deleting file. Please try again.')
    }
    
    this.hideDeleteModal()
  }
}

