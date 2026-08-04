import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["folderDropZone"]

  connect() {
    // Set up drop zones for folders when controller connects
    setTimeout(() => {
      this.setupFolderDropZones()
    }, 100)
  }

  toggleSelect(event) {
    // Don't toggle if clicking on action buttons or links
    if (event.target.closest('a, button')) {
      return
    }
    
    const fileItem = event.currentTarget
    const checkbox = fileItem.querySelector('.file-checkbox')
    
    if (checkbox) {
      checkbox.checked = !checkbox.checked
      checkbox.dispatchEvent(new Event('change', { bubbles: true }))
    }
  }

  updateSelection(event) {
    const checkbox = event.target
    const fileItem = checkbox.closest('.file-item')
    
    if (checkbox.checked) {
      fileItem.classList.add('ring-2', 'ring-theme-accent')
    } else {
      fileItem.classList.remove('ring-2', 'ring-theme-accent')
    }

    // Update bulk actions bar
    const storageController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller*="storage"]'),
      'storage'
    )
    if (storageController) {
      storageController.updateBulkActionsBar()
    }
  }

  handleDragStart(event) {
    event.dataTransfer.effectAllowed = 'move'
    event.dataTransfer.setData('text/plain', event.currentTarget.dataset.fileId)
    event.currentTarget.classList.add('opacity-50')
  }

  handleDragEnd(event) {
    event.currentTarget.classList.remove('opacity-50')
  }

  deleteFile(event) {
    event.stopPropagation()
    const fileId = event.currentTarget.dataset.fileId
    const fileName = event.currentTarget.closest('.file-item').querySelector('.text-theme-primary').textContent
    
    const storageController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller*="storage"]'),
      'storage'
    )
    
    if (storageController) {
      storageController.showDeleteModal(
        `Are you sure you want to delete "${fileName}"?`,
        () => {
          storageController.performDelete(fileId)
        }
      )
    }
  }

  setupFolderDropZones() {
    // Add drop handlers to all folder items
    document.querySelectorAll('.folder-tree-item').forEach(folderItem => {
      // Check if already has listeners
      if (folderItem.dataset.dropZoneSetup === 'true') {
        return
      }
      folderItem.dataset.dropZoneSetup = 'true'
      
      folderItem.addEventListener('dragover', (e) => {
        e.preventDefault()
        e.stopPropagation()
        e.dataTransfer.dropEffect = 'move'
        const folderRow = folderItem.querySelector('.flex.items-center')
        if (folderRow) {
          folderRow.classList.add('bg-theme-accent', 'ring-2', 'ring-theme-accent')
        }
      })
      
      folderItem.addEventListener('drop', (e) => {
        this.handleFolderDrop(e, folderItem)
      })
      
      folderItem.addEventListener('dragleave', (e) => {
        e.preventDefault()
        e.stopPropagation()
        const folderRow = folderItem.querySelector('.flex.items-center')
        if (folderRow) {
          folderRow.classList.remove('bg-theme-accent', 'ring-2', 'ring-theme-accent')
        }
      })
    })
  }

  async handleFolderDrop(event, folderItem) {
    event.preventDefault()
    event.stopPropagation()
    const folderRow = folderItem.querySelector('.flex.items-center')
    if (folderRow) {
      folderRow.classList.remove('bg-theme-accent', 'ring-2', 'ring-theme-accent')
    }
    
    const fileId = event.dataTransfer.getData('text/plain')
    const folderId = folderItem.dataset.folderId
    
    if (!fileId || !folderId) return
    
    // Get storage controller to make the API call
    const storageController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller*="storage"]'),
      'storage'
    )
    
    if (storageController) {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      if (!csrfToken) {
        window.showToast('error', 'Security token missing. Please refresh the page.')
        return
      }
      
      try {
        const response = await fetch(`/guilds/${storageController.guildIdValue}/file_entries/bulk_move`, {
          method: 'PATCH',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken,
            'Accept': 'application/json'
          },
          body: JSON.stringify({
            file_ids: [fileId],
            folder_id: folderId
          })
        })
        
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }
        
        const data = await response.json()
        
        if (data.success) {
          window.location.reload()
        } else {
          window.showToast('error', 'Error moving file: ' + (data.error || 'Unknown error'))
        }
      } catch (error) {
        console.error('Error:', error)
        window.showToast('error', 'Error moving file: ' + error.message)
      }
    }
  }
}
