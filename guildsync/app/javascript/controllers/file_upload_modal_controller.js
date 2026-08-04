import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fileInput"]
  static values = {
    guildId: String,
    folderId: String
  }

  selectFiles() {
    this.fileInputTarget.click()
  }

  handleFiles(event) {
    const files = event.target.files
    const fileList = document.getElementById('file-list')
    fileList.innerHTML = ''

    Array.from(files).forEach((file, index) => {
      const fileItem = document.createElement('div')
      fileItem.className = 'flex items-center justify-between p-2 bg-theme-secondary rounded'
      fileItem.innerHTML = `
        <span class="text-theme-primary text-sm">${file.name}</span>
        <span class="text-theme-secondary text-xs">${this.formatFileSize(file.size)}</span>
      `
      fileList.appendChild(fileItem)
    })

    this.files = files
  }

  async uploadFiles() {
    if (!this.files || this.files.length === 0) {
      window.showToast('warning', 'Please select files to upload')
      return
    }

    const formData = new FormData()
    Array.from(this.files).forEach(file => {
      formData.append('files[]', file)
    })
    
    if (this.folderIdValue) {
      formData.append('folder_id', this.folderIdValue)
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/file_entries`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': csrfToken
        },
        body: formData
      })

      const data = await response.json()
      
      if (data.success) {
        document.getElementById('upload-modal').classList.add('hidden')
        location.reload() // Reload to show new files
      } else {
        window.showToast('error', 'Error uploading files: ' + (data.error || 'Unknown error'))
      }
    } catch (error) {
      console.error('Error:', error)
      window.showToast('error', 'Error uploading files. Please try again.')
    }
  }

  formatFileSize(bytes) {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
  }
}

