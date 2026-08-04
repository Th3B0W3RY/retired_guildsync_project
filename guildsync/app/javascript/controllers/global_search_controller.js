import { Controller } from "@hotwired/stimulus"

// Type icons for search results
const TYPE_ICONS = {
  page: `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
  </svg>`,
  event: `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
  </svg>`,
  poll: `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"></path>
  </svg>`,
  battle: `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"></path>
  </svg>`,
  scheduled_event: `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
  </svg>`,
  document: `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
  </svg>`,
  loot_roll: `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"></path>
  </svg>`
}

const TYPE_LABELS = {
  page: "Quick Navigation",
  event: "Event",
  poll: "Poll",
  battle: "Guild Battle",
  scheduled_event: "Scheduled Event",
  document: "Document",
  loot_roll: "Loot Roll"
}

export default class extends Controller {
  static targets = ["input", "results", "resultsList", "loading", "empty", "clearBtn"]
  
  connect() {
    this.debounceTimer = null
    this.selectedIndex = -1
    this.currentResults = []
    
    // Close dropdown when clicking outside
    this.clickOutsideHandler = (event) => {
      if (!this.element.contains(event.target)) {
        this.hideResults()
      }
    }
    document.addEventListener("click", this.clickOutsideHandler)
  }
  
  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler)
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }
  
  onInput() {
    const query = this.inputTarget.value.trim()
    
    // Show/hide clear button
    if (query.length > 0) {
      this.clearBtnTarget.classList.remove("hidden")
    } else {
      this.clearBtnTarget.classList.add("hidden")
      this.hideResults()
      return
    }
    
    // Debounce search
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
    
    this.debounceTimer = setTimeout(() => {
      if (query.length >= 2) {
        this.search(query)
      }
    }, 300)
  }
  
  onKeydown(event) {
    if (!this.resultsTarget.classList.contains("hidden")) {
      switch (event.key) {
        case "ArrowDown":
          event.preventDefault()
          this.moveSelection(1)
          break
        case "ArrowUp":
          event.preventDefault()
          this.moveSelection(-1)
          break
        case "Enter":
          event.preventDefault()
          this.selectCurrent()
          break
        case "Escape":
          event.preventDefault()
          this.hideResults()
          this.inputTarget.blur()
          break
      }
    } else if (event.key === "Escape") {
      this.inputTarget.blur()
    }
  }
  
  onFocus() {
    if (this.currentResults.length > 0) {
      this.showResults()
    }
  }
  
  async search(query) {
    this.showLoading()
    
    try {
      const response = await fetch(`/search?q=${encodeURIComponent(query)}`, {
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })
      
      if (!response.ok) {
        throw new Error("Search failed")
      }
      
      const data = await response.json()
      this.currentResults = data.results || []
      this.renderResults(data)
    } catch (error) {
      console.error("Search error:", error)
      this.showEmpty()
    }
  }
  
  renderResults(data) {
    this.hideLoading()
    this.selectedIndex = -1
    
    if (!data.results || data.results.length === 0) {
      this.showEmpty()
      return
    }
    
    this.emptyTarget.classList.add("hidden")
    
    // Group results by type
    const grouped = this.groupByType(data.results)
    
    let html = ""
    for (const [type, items] of Object.entries(grouped)) {
      html += this.renderGroup(type, items)
    }
    
    this.resultsListTarget.innerHTML = html
    this.showResults()
  }
  
  groupByType(results) {
    return results.reduce((groups, result) => {
      const type = result.type
      if (!groups[type]) {
        groups[type] = []
      }
      groups[type].push(result)
      return groups
    }, {})
  }
  
  renderGroup(type, items) {
    const icon = TYPE_ICONS[type] || TYPE_ICONS.document
    const label = TYPE_LABELS[type] || type
    
    let html = `
      <div class="py-2">
        <div class="px-4 py-1 text-xs font-semibold text-theme-secondary uppercase tracking-wider flex items-center gap-2">
          ${icon}
          <span>${label}s</span>
        </div>
        <div class="divide-y divide-theme-primary/50">`
    
    items.forEach((item, index) => {
      const globalIndex = this.currentResults.indexOf(item)
      html += this.renderItem(item, globalIndex)
    })
    
    html += `</div></div>`
    return html
  }
  
  renderItem(item, index) {
    const highlights = item.highlights || {}
    const title = highlights.title || this.escapeHtml(item.title)
    const description = highlights.description || this.escapeHtml(item.description || "")
    
    return `
      <a href="${item.url}" 
         class="search-result-item block px-4 py-3 hover:bg-theme-secondary cursor-pointer transition-colors"
         data-index="${index}"
         data-action="mouseenter->global-search#onHover click->global-search#onClick">
        <div class="flex items-start gap-3">
          <div class="flex-1 min-w-0">
            <div class="text-theme-primary font-medium truncate">${title}</div>
            ${description ? `<div class="text-theme-secondary text-sm truncate mt-0.5">${description}</div>` : ""}
            ${item.guild_name ? `<div class="text-theme-secondary text-xs mt-1 flex items-center gap-1">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"></path>
              </svg>
              <span>${this.escapeHtml(item.guild_name)}</span>
            </div>` : ""}
          </div>
        </div>
      </a>`
  }
  
  moveSelection(delta) {
    const items = this.resultsListTarget.querySelectorAll(".search-result-item")
    if (items.length === 0) return
    
    // Clear previous selection
    items.forEach(item => item.classList.remove("bg-theme-secondary"))
    
    // Update index
    this.selectedIndex += delta
    if (this.selectedIndex < 0) this.selectedIndex = items.length - 1
    if (this.selectedIndex >= items.length) this.selectedIndex = 0
    
    // Highlight new selection
    const selected = items[this.selectedIndex]
    selected.classList.add("bg-theme-secondary")
    selected.scrollIntoView({ block: "nearest" })
  }
  
  selectCurrent() {
    if (this.selectedIndex >= 0 && this.currentResults[this.selectedIndex]) {
      window.location.href = this.currentResults[this.selectedIndex].url
    }
  }
  
  onHover(event) {
    const items = this.resultsListTarget.querySelectorAll(".search-result-item")
    items.forEach(item => item.classList.remove("bg-theme-secondary"))
    
    const index = parseInt(event.currentTarget.dataset.index, 10)
    if (!isNaN(index)) {
      this.selectedIndex = index
      event.currentTarget.classList.add("bg-theme-secondary")
    }
  }
  
  onClick(event) {
    // Let the link navigate naturally
  }
  
  clear() {
    this.inputTarget.value = ""
    this.clearBtnTarget.classList.add("hidden")
    this.hideResults()
    this.currentResults = []
    this.inputTarget.focus()
  }
  
  showResults() {
    this.resultsTarget.classList.remove("hidden")
  }
  
  hideResults() {
    this.resultsTarget.classList.add("hidden")
  }
  
  showLoading() {
    this.resultsTarget.classList.remove("hidden")
    this.loadingTarget.classList.remove("hidden")
    this.emptyTarget.classList.add("hidden")
    this.resultsListTarget.innerHTML = ""
  }
  
  hideLoading() {
    this.loadingTarget.classList.add("hidden")
  }
  
  showEmpty() {
    this.hideLoading()
    this.emptyTarget.classList.remove("hidden")
    this.resultsListTarget.innerHTML = ""
    this.showResults()
  }
  
  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
