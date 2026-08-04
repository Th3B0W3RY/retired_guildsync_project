import { Controller } from "@hotwired/stimulus"
import { generateHTML } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Image from "@tiptap/extension-image"

export default class extends Controller {
  static values = { content: String }

  connect() {
    try {
      // Default empty document structure
      const defaultContent = { type: "doc", content: [] }
      
      // Parse content from value
      let content
      try {
        const parsed = JSON.parse(this.contentValue || JSON.stringify(defaultContent))
        
        // Validate content structure
        if (parsed && typeof parsed === 'object') {
          // If it's an empty object or doesn't have the right structure, use default
          if (!parsed.type || parsed.type !== 'doc' || !Array.isArray(parsed.content)) {
            console.warn("Invalid content structure, using default:", parsed)
            content = defaultContent
          } else {
            content = parsed
          }
        } else {
          content = defaultContent
        }
      } catch (parseError) {
        console.warn("Error parsing content JSON, using default:", parseError)
        content = defaultContent
      }
      
      // Generate HTML from content (include Image so embedded images render)
      const html = generateHTML(content, [StarterKit, Image.configure({ inline: false })])
      this.element.innerHTML = html || '<p class="text-theme-secondary">No content</p>'
    } catch (e) {
      console.error("Error rendering document content:", e)
      this.element.innerHTML = '<p class="text-red-400">Error rendering document content. Please try editing the document.</p>'
    }
  }
}

