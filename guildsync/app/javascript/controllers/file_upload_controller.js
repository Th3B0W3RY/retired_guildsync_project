import { Controller } from "@hotwired/stimulus"
import { devLog, devError } from "../helpers/dev_console"

export default class extends Controller {
  static targets = ["fileInput"]
  static values = {
    guildId: String,
    folderId: String
  }

  connect() {
    // Prevent default drag behaviors globally to stop browser from opening files
    this.boundPreventDefaults = this.preventDefaults.bind(this)
    this.boundHandleDrop = this.handleGlobalDrop.bind(this)
    this.boundHandlePaste = this.handlePaste.bind(this)
    
    document.addEventListener('dragover', this.boundPreventDefaults, false)
    document.addEventListener('drop', this.boundHandleDrop, false)
    document.addEventListener('paste', this.boundHandlePaste)
  }

  disconnect() {
    document.removeEventListener('dragover', this.boundPreventDefaults, false)
    document.removeEventListener('drop', this.boundHandleDrop, false)
    document.removeEventListener('paste', this.boundHandlePaste)
  }

  preventDefaults(event) {
    // Only prevent if not dragging a file item (file-grid handles those)
    if (event.dataTransfer?.types?.includes('text/plain')) {
      // This might be a file being dragged, let file-grid handle it
      return
    }
    // Always prevent default to stop browser from opening files
    event.preventDefault()
    event.stopPropagation()
  }

  handleGlobalDrop(event) {
    // Don't interfere with file drag/drop to folders
    if (event.target.closest('.folder-tree-item')) {
      return
    }
    
    // Prevent default globally to stop browser from opening files
    event.preventDefault()
    event.stopPropagation()
    
    // Only process if dropped on our drop zone or anywhere on the page when drop zone is visible
    const dropZone = this.element
    if (dropZone && (dropZone.contains(event.target) || event.target === dropZone || dropZone.offsetParent !== null)) {
      this.handleDrop(event)
    }
  }

  handleDragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = 'copy'
    this.element.classList.add('border-theme-accent', 'bg-slate-700/80', 'scale-[1.02]')
  }

  handleDragLeave(event) {
    event.preventDefault()
    event.stopPropagation()
    // Only remove highlight if we're actually leaving the drop zone
    if (!this.element.contains(event.relatedTarget)) {
      this.element.classList.remove('border-theme-accent', 'bg-slate-700/80', 'scale-[1.02]')
    }
  }

  handleDrop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.element.classList.remove('border-theme-accent', 'bg-slate-700/80', 'scale-[1.02]')
    
    const files = event.dataTransfer.files
    if (files && files.length > 0) {
      this.uploadFiles(files)
    }
  }

  handlePaste(event) {
    // Only handle paste if the drop zone is visible and user is focused on the page
    if (!this.element.offsetParent) return
    
    const items = event.clipboardData?.items
    if (!items) return

    const files = []
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.kind === 'file') {
        const file = item.getAsFile()
        if (file) {
          files.push(file)
        }
      }
    }

    if (files.length > 0) {
      event.preventDefault()
      this.uploadFiles(files)
    }
  }

  selectFiles(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    // Check if fileInput target exists
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    } else {
      devError("File input target not found. Available targets:", this.targets)
    }
  }

  handleFileSelect(event) {
    const files = event.target.files
    if (files && files.length > 0) {
      this.uploadFiles(files)
      // Reset the input so the same file can be selected again
      event.target.value = ''
    }
  }

  async uploadFiles(files) {
    if (!files || files.length === 0) return

    const formData = new FormData()
    Array.from(files).forEach(file => {
      formData.append('files[]', file)
    })
    
    if (this.folderIdValue) {
      formData.append('folder_id', this.folderIdValue)
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) {
      window.showToast('error', 'Security token missing. Please refresh the page and try again.')
      return
    }

    // Show loading state
    const button = this.element.querySelector('button')
    const originalText = button?.textContent
    if (button) {
      button.disabled = true
      button.textContent = 'Uploading...'
    }

    try {
      const url = `/guilds/${this.guildIdValue}/file_entries`
      devLog("Uploading to:", url)
      
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': csrfToken,
          'Accept': 'application/json'
        },
        body: formData,
        credentials: 'same-origin'
      })

      if (!response.ok) {
        const errorText = await response.text()
        let errorMessage = `HTTP error! status: ${response.status}`
        try {
          const errorData = JSON.parse(errorText)
          errorMessage = errorData.error || errorMessage
        } catch (e) {
          errorMessage = errorText || errorMessage
        }
        throw new Error(errorMessage)
      }

      const data = await response.json()
      
      if (data.success) {
        location.reload() // Reload to show new files
      } else {
        window.showToast('error', 'Error uploading files: ' + (data.error || 'Unknown error'))
        if (button) {
          button.disabled = false
          button.textContent = originalText
        }
      }
    } catch (error) {
      devError("Upload error:", error)
      let errorMessage = 'Error uploading files'
      if (error.message) {
        errorMessage += ': ' + error.message
      } else if (error.name === 'TypeError' && error.message.includes('Failed to fetch')) {
        errorMessage += ': Unable to connect to server. Please check your connection and try again.'
      } else {
        errorMessage += ': ' + (error.toString() || 'Unknown error')
      }
      window.showToast('error', errorMessage)
      if (button) {
        button.disabled = false
        button.textContent = originalText
      }
    }
  }
}

