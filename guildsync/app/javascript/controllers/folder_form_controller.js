import { Controller } from "@hotwired/stimulus"
import { devLog, devError } from "../helpers/dev_console"

export default class extends Controller {
  connect() {
    // Listen for form submission events
    this.boundHandleSubmit = this.handleSubmit.bind(this)
    this.element.addEventListener('submit', this.boundHandleSubmit)
    
    // Make sure cancel button works - find it within the form
    const cancelButton = this.element.querySelector('button[type="button"]')
    if (cancelButton && cancelButton.textContent.trim() === 'Cancel') {
      cancelButton.addEventListener('click', (e) => {
        e.preventDefault()
        e.stopPropagation()
        e.stopImmediatePropagation()
        const modal = document.getElementById('create-folder-modal')
        if (modal) {
          modal.classList.add('hidden')
        }
        this.element.reset()
        return false
      }, true) // Use capture phase to ensure it fires first
    }
  }

  handleSubmit(event) {
    // Prevent default form submission
    event.preventDefault()
    event.stopPropagation()
    
    const form = event.target
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    
    // Get folder name from the form - use the ID selector first (most reliable)
    const folderNameInput = form.querySelector('#folder-name-input') || 
                            form.querySelector('input[name="folder[name]"]') ||
                            form.querySelector('input[type="text"]')
    
    // Read the value directly from the input element
    let folderName = ''
    if (folderNameInput) {
      // Get value directly from the input
      folderName = folderNameInput.value || ''
      folderName = folderName.trim()
      
      devLog("Folder name input found:", folderNameInput)
      devLog("Folder name value:", folderName)
    } else {
      devError("Folder name input not found!")
    }
    
    // Validate folder name BEFORE creating FormData
    // Only show alert if the field is actually empty
    if (!folderName || folderName.length === 0) {
      window.showToast('warning', 'Please enter a folder name')
      if (folderNameInput) {
        folderNameInput.focus()
      }
      return
    }
    
    // Build FormData properly - ensure folder[name] is set correctly
    const formData = new FormData(form)
    
    devLog("All FormData entries before fix:")
    for (let pair of formData.entries()) {
      devLog("  ", pair[0], "=", pair[1])
    }
    
    // Verify folder name is in FormData - check both possible formats
    let formDataName = formData.get('folder[name]')
    if (!formDataName) {
      // Check if it's just 'name' instead of 'folder[name]'
      const nameValue = formData.get('name')
      if (nameValue && folderName) {
        // Remove the flat 'name' and add it as 'folder[name]'
        formData.delete('name')
        formData.set('folder[name]', folderName)
        formDataName = folderName
      }
    }
    
    // If still not found, manually add it
    if (!formDataName && folderName) {
      formData.set('folder[name]', folderName)
      formDataName = folderName
    }
    
    devLog("Folder name in FormData after fix:", formDataName)
    
    fetch(form.action, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json'
      },
      body: formData
    })
    .then(response => {
      // Check if response is actually JSON
      const contentType = response.headers.get('content-type')
      if (!contentType || !contentType.includes('application/json')) {
        // If not JSON, read as text to see what we got
        return response.text().then(text => {
          devError("Non-JSON response received:", text.substring(0, 200))
          throw new Error('Server returned non-JSON response. Please check the server logs.')
        })
      }
      
      if (!response.ok) {
        return response.json().then(err => Promise.reject(err))
      }
      return response.json()
    })
    .then(data => {
      if (data.success) {
        // Close modal first
        const modal = document.getElementById('create-folder-modal')
        if (modal) {
          modal.classList.add('hidden')
        }
        // Clear the form
        form.reset()
        // Extract guild ID from form action URL and redirect to storage page
        const guildIdMatch = form.action.match(/\/guilds\/(\d+)\/folders/)
        const guildId = guildIdMatch ? guildIdMatch[1] : null
        
        if (guildId) {
          // Redirect to file storage page to show the new folder
          window.location.href = `/guilds/${guildId}/storage`
        } else {
          // Fallback to reload if we can't extract guild ID
          window.location.reload()
        }
      } else {
        window.showToast('error', 'Error creating folder: ' + (data.error || 'Unknown error'))
      }
    })
    .catch(error => {
      devError("Error:", error)
      const errorMessage = error.error || error.message || 'Error creating folder. Please try again.'
      window.showToast('error', errorMessage)
      // Re-enable the form in case of error
      const submitButton = form.querySelector('input[type="submit"], button[type="submit"]')
      if (submitButton) {
        submitButton.disabled = false
      }
    })
  }

  disconnect() {
    // Clean up event listener
    if (this.boundHandleSubmit) {
      this.element.removeEventListener('submit', this.boundHandleSubmit)
    }
  }
}

