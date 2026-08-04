import { Controller } from "@hotwired/stimulus"
import { devLog, devWarn, devError } from "../helpers/dev_console"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"
import Underline from "@tiptap/extension-underline"

export default class extends Controller {
  static targets = ["input", "editor", "source"]
  static values = { uploadUrl: String, outputFormat: { type: String, default: "json" } }

  connect() {
    devLog("EditorController connected", this.element)
    devLog("Input target:", this.inputTarget)
    devLog("Editor target:", this.editorTarget)

    // Parse initial content - try JSON first, then HTML
    let initialContent = ""
    try {
      const inputValue = this.inputTarget.value
      if (inputValue && inputValue.trim() !== "") {
        try {
          const parsed = JSON.parse(inputValue)
          // Validate parsed content has proper structure
          if (parsed && typeof parsed === 'object' && (parsed.type === 'doc' || Array.isArray(parsed))) {
            initialContent = parsed
          } else {
            // Invalid JSON structure, use empty content
            initialContent = ""
          }
        } catch (e) {
          // If not JSON, use as HTML
          initialContent = inputValue
        }
      }
    } catch (e) {
      devWarn("Error parsing initial content:", e)
      initialContent = ""
    }

    devLog("Initializing Tiptap editor with content:", initialContent)
    
    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [
        StarterKit,
        Link.configure({
          openOnClick: false,
          HTMLAttributes: {
            target: '_blank',
            rel: 'noopener noreferrer'
          }
        }),
        Image.configure({ inline: false }),
        Underline
      ],
      content: initialContent || "",
      autofocus: false,
      editable: true,
      onCreate: ({ editor }) => {
        devLog("Tiptap editor created, initial content:", editor.getJSON())
      },
      editorProps: {
        attributes: {
          class: 'prose prose-invert max-w-none focus:outline-none',
          'data-placeholder': 'Start typing...'
        },
        handleKeyDown: (view, event) => {
          // Handle Tab key for indentation
          if (event.key === 'Tab' && !event.ctrlKey && !event.metaKey && !event.altKey) {
            event.preventDefault()
            
            if (event.shiftKey) {
              // Shift+Tab: Outdent (remove indentation)
              if (this.editor.isActive('blockquote')) {
                // Lift out of blockquote
                this.editor.chain().focus().lift('blockquote').run()
              } else if (this.editor.isActive('listItem')) {
                // Lift list item (outdent in list)
                this.editor.chain().focus().liftListItem('listItem').run()
              }
            } else {
              // Tab: Indent (add indentation)
              if (this.editor.isActive('listItem')) {
                // Sink list item (indent in list) - Tiptap handles this
                this.editor.chain().focus().sinkListItem('listItem').run()
              } else {
                // Wrap current paragraph/block in blockquote for visual indentation
                const { state } = view
                const { selection } = state
                const { $from, $to } = selection
                
                // Check if we're at the start of a paragraph
                if ($from.parent.type.name === 'paragraph' && $from.parentOffset === 0) {
                  // Wrap the paragraph in a blockquote
                  this.editor.chain().focus().toggleBlockquote().run()
                } else {
                  // Insert 4 spaces for inline indentation
                  this.editor.chain().focus().insertContent('    ').run()
                }
              }
            }
            return true
          }
          return false
        },
        handlePaste: (view, event) => {
          const html = event.clipboardData?.getData("text/html")
          if (html && html.trim() !== "") {
            event.preventDefault()
            this.editor.chain().focus().insertContent(html).run()
            return true
          }
          const items = event.clipboardData?.items
          if (!items) return false
          for (const item of items) {
            if (item.type.indexOf("image") !== -1) {
              event.preventDefault()
              const file = item.getAsFile()
              if (file) this.uploadImageFile(file)
              return true
            }
          }
          return false
        }
      },
      onUpdate: ({ editor }) => {
        this.syncInputFromEditor(editor)
        this.syncSourceFromEditor(editor)
      },
      onFocus: () => {
        devLog("Editor focused")
      },
      onBlur: () => {
        devLog("Editor blurred")
      }
    })

    // Keep the editor keyboard-focusable without overriding native caret placement.
    this.editorTarget.setAttribute('contenteditable', 'true')
    this.editorTarget.setAttribute('tabindex', '0')
    this.editorTarget.style.cursor = 'text'
    this.editorTarget.style.outline = 'none'

    // Handle Tab key directly on the editor element to prevent focus navigation
    this.editorTarget.addEventListener('keydown', (e) => {
      if (e.key === 'Tab' && !e.ctrlKey && !e.metaKey && !e.altKey) {
        e.preventDefault()
        e.stopPropagation()
        e.stopImmediatePropagation()
        
        if (e.shiftKey) {
          // Shift+Tab: Outdent
          if (this.editor.isActive('blockquote')) {
            this.editor.chain().focus().lift('blockquote').run()
          } else if (this.editor.isActive('listItem')) {
            this.editor.chain().focus().liftListItem('listItem').run()
          }
        } else {
          // Tab: Indent
          if (this.editor.isActive('listItem')) {
            this.editor.chain().focus().sinkListItem('listItem').run()
          } else {
            // Insert 4 spaces for indentation
            this.editor.chain().focus().insertContent('    ').run()
          }
        }
        return false
      }
    }, true) // Use capture phase to catch it early

    // Ensure content is saved before form submission
    // Find the form - it might be a parent of the editor container
    const form = this.element.closest('form')
    devLog("Form found:", form)
    if (form) {
      const submitHandler = (e) => {
        devLog("Form submit event fired - capturing editor content")
        // Capture current editor content before form submission
        if (this.editor) {
          this.applySourceToEditor()
          this.syncInputFromEditor(this.editor)
          // Double-check the value is set
          setTimeout(() => {
            devLog("Hidden field value after timeout:", this.inputTarget?.value)
          }, 100)
        } else {
          devWarn("Editor not available on form submit")
        }
      }
      // Use both capture and bubble phases to ensure we catch it
      form.addEventListener('submit', submitHandler, true) // capture phase
      form.addEventListener('submit', submitHandler, false) // bubble phase
      devLog("Form submit handler attached (both phases)")
    } else {
      devError("Form not found for editor! Element:", this.element, "Parent:", this.element.parentElement)
    }

    devLog("Tiptap initialized successfully")
    devLog("Editor instance:", this.editor)
    devLog("Editor content on init:", this.editor ? this.editor.getJSON() : "No editor")
    
    // Force an initial update to ensure hidden field has content
    if (this.editor && this.inputTarget) {
      setTimeout(() => {
        this.syncInputFromEditor(this.editor)
        this.syncSourceFromEditor(this.editor)
      }, 500)
    }

    this._preventBlurHandler = (event) => event.preventDefault()
    this._preventBlurButtons = Array.from(this.element.querySelectorAll("[data-editor-prevent-blur]"))
    this._preventBlurButtons.forEach((button) => {
      button.addEventListener("mousedown", this._preventBlurHandler)
    })
  }

  syncInputFromEditor(editor) {
    if (!editor) return
    if (!this.hasInputTarget) {
      devError("Input target not found!")
      return
    }

    try {
      if (this.outputFormatValue === "html") {
        const html = editor.getHTML()
        this.inputTarget.value = html
        devLog("HTML content updated in hidden field")
      } else {
        const content = editor.getJSON()
        const contentString = JSON.stringify(content)
        this.inputTarget.value = contentString
        devLog("JSON content updated in hidden field:", content)
      }
      devLog("Hidden field value:", this.inputTarget.value)
    } catch (error) {
      devError("Error syncing editor content:", error)
    }
  }

  syncSourceFromEditor(editor) {
    if (!this.hasSourceTarget || !editor) return
    this.sourceTarget.value = editor.getHTML()
  }

  applySourceToEditor() {
    if (!this.hasSourceTarget || !this.editor) return
    const html = this.sourceTarget.value.toString()
    this.editor.commands.setContent(html, true)
  }

  toggleSource(event) {
    event.preventDefault()
    if (!this.hasSourceTarget) return
    const isHidden = this.sourceTarget.classList.contains("hidden")
    if (isHidden) {
      this.syncSourceFromEditor(this.editor)
      this.sourceTarget.classList.remove("hidden")
      this.sourceTarget.focus()
    } else {
      this.applySourceToEditor()
      this.sourceTarget.classList.add("hidden")
      this.editor?.commands.focus()
    }
  }

  // Toolbar actions
  bold(event) {
    event.preventDefault()
    this.editor?.chain().focus().toggleBold().run()
  }

  italic(event) {
    event.preventDefault()
    this.editor?.chain().focus().toggleItalic().run()
  }

  underline(event) {
    event.preventDefault()
    this.editor?.chain().focus().toggleUnderline().run()
  }

  heading1(event) {
    event.preventDefault()
    this.editor?.chain().focus().toggleHeading({ level: 1 }).run()
  }

  heading2(event) {
    event.preventDefault()
    this.editor?.chain().focus().toggleHeading({ level: 2 }).run()
  }

  bulletList(event) {
    event.preventDefault()
    this.editor?.chain().focus().toggleBulletList().run()
  }

  orderedList(event) {
    event.preventDefault()
    this.editor?.chain().focus().toggleOrderedList().run()
  }

  addLink(event) {
    event.preventDefault()
    const url = window.prompt("Enter URL:")
    if (url) {
      this.editor?.chain().focus().extendMarkRange("link").setLink({ href: url }).run()
    }
  }

  addVideo(event) {
    event.preventDefault()
    window.showToast('info', "Video embedding is not yet supported.")
  }

  uploadImage(event) {
    event.preventDefault()
    if (!this.hasUploadUrlValue) {
      devWarn("Editor: upload URL not set, cannot upload image")
      return
    }
    const input = document.createElement("input")
    input.type = "file"
    input.accept = "image/jpeg,image/png,image/gif,image/webp"
    input.onchange = (e) => {
      const file = e.target.files?.[0]
      if (file) this.uploadImageFile(file)
    }
    input.click()
  }

  async uploadImageFile(file) {
    if (!this.hasUploadUrlValue || !this.editor) return
    const url = this.uploadUrlValue
    const formData = new FormData()
    formData.append("image", file)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const headers = { "X-CSRF-Token": csrfToken, "Accept": "application/json" }
    try {
      const res = await fetch(url, { method: "POST", body: formData, headers, credentials: "same-origin" })
      const data = await res.json().catch(() => ({}))
      if (res.ok && data.url) {
        this.editor.chain().focus().setImage({ src: data.url }).run()
      } else {
        if (!res.ok) devError("Upload image response", res.status, data)
        const msg = data.error_detail ? `${data.error} — ${data.error_detail}` : (data.error || "Image upload failed")
        window.showToast('error', msg)
      }
    } catch (err) {
      devError("Image upload error:", err)
      window.showToast('error', "Image upload failed. Please try again.")
    }
  }

  disconnect() {
    if (this._preventBlurButtons && this._preventBlurHandler) {
      this._preventBlurButtons.forEach((button) => {
        button.removeEventListener("mousedown", this._preventBlurHandler)
      })
      this._preventBlurButtons = null
      this._preventBlurHandler = null
    }
    if (this.editor) {
      this.editor.destroy()
      this.editor = null
    }
  }
}
