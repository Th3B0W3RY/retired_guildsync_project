import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "searchInput", "searchDropdown", "searchResults", "searchLoading", "searchEmpty",
    "conversationPanel", "emptyState", "thread", "recipientAvatar", "recipientName", "recipientBadge",
    "composer", "sendBtn", "charCount"
  ]
  static values = {
    guildId: Number,
    currentUserId: Number,
    searchUrl: String,
    conversationUrl: String,
    sendUrl: String
  }

  connect() {
    this.debounceTimer = null
    this.selectedRecipient = null
    this.clickOutsideHandler = (e) => {
      if (!this.element.contains(e.target)) this.hideSearchDropdown()
    }
    document.addEventListener("click", this.clickOutsideHandler)
    if (this.hasComposerTarget) {
      this.composerTarget.addEventListener("input", () => this.updateCharCount())
    }
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler)
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
  }

  onSearchInput() {
    const q = this.searchInputTarget.value.trim()
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    if (!q || q.length < 1) {
      this.hideSearchDropdown()
      return
    }
    this.debounceTimer = setTimeout(() => this.fetchRecipients(q), 280)
  }

  onSearchFocus() {
    const q = this.searchInputTarget.value.trim()
    if (q.length >= 1) this.fetchRecipients(q)
  }

  async fetchRecipients(q) {
    if (!this.hasSearchDropdownTarget) return
    this.searchDropdownTarget.classList.remove("hidden")
    this.searchResultsTarget.innerHTML = ""
    if (this.hasSearchLoadingTarget) this.searchLoadingTarget.classList.remove("hidden")
    if (this.hasSearchEmptyTarget) this.searchEmptyTarget.classList.add("hidden")
    try {
      const url = `${this.searchUrlValue}?q=${encodeURIComponent(q)}`
      const resp = await fetch(url, { headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" } })
      const data = await resp.json()
      if (this.hasSearchLoadingTarget) this.searchLoadingTarget.classList.add("hidden")
      if (!Array.isArray(data) || data.length === 0) {
        if (this.hasSearchEmptyTarget) {
          this.searchEmptyTarget.textContent = "No results. Try another search."
          this.searchEmptyTarget.classList.remove("hidden")
        }
        return
      }
      data.forEach((r) => {
        const row = document.createElement("button")
        row.type = "button"
        row.className = "w-full flex items-center gap-3 px-4 py-2.5 text-left hover:bg-theme-secondary rounded-lg transition-colors"
        row.dataset.id = r.id
        row.dataset.name = r.name || r.username || ""
        row.dataset.username = r.username || ""
        row.dataset.type = r.type || "member"
        row.innerHTML = `
          <div class="w-10 h-10 rounded-full bg-theme-accent/20 flex items-center justify-center text-theme-accent font-semibold">${(r.name || r.username || "?").charAt(0).toUpperCase()}</div>
          <div class="flex-1 min-w-0">
            <div class="font-medium text-theme-primary truncate">${this.escapeHtml(r.name || r.username)}</div>
            <div class="text-sm text-theme-secondary truncate">${this.escapeHtml(r.username)} ${r.type === "owner" ? "• Guild owner" : ""}</div>
          </div>
        `
        row.addEventListener("click", () => this.selectRecipient(r))
        this.searchResultsTarget.appendChild(row)
      })
    } catch (err) {
      if (this.hasSearchLoadingTarget) this.searchLoadingTarget.classList.add("hidden")
      if (this.hasSearchEmptyTarget) {
        this.searchEmptyTarget.textContent = "Search failed. Try again."
        this.searchEmptyTarget.classList.remove("hidden")
      }
    }
  }

  selectRecipient(recipient) {
    this.selectedRecipient = recipient
    this.searchInputTarget.value = recipient.name || recipient.username
    this.hideSearchDropdown()
    this.recipientAvatarTarget.textContent = (recipient.name || recipient.username || "?").charAt(0).toUpperCase()
    this.recipientNameTarget.textContent = recipient.name || recipient.username
    this.recipientBadgeTarget.textContent = recipient.type === "owner" ? "Guild owner" : "Member"
    this.conversationPanelTarget.classList.remove("hidden")
    this.emptyStateTarget.classList.add("hidden")
    this.threadTarget.innerHTML = ""
    if (this.hasComposerTarget) this.composerTarget.value = ""
    this.updateCharCount()
    this.loadConversation()
  }

  hideSearchDropdown() {
    if (this.hasSearchDropdownTarget) this.searchDropdownTarget.classList.add("hidden")
  }

  async loadConversation() {
    if (!this.selectedRecipient) return
    const url = this.conversationUrlValue.replace("__RECIPIENT__", this.selectedRecipient.id)
    try {
      const resp = await fetch(url, { headers: { "Accept": "application/json" } })
      const messages = await resp.json()
      if (!Array.isArray(messages)) return
      this.threadTarget.innerHTML = ""
      messages.forEach((m) => this.appendMessage(m))
      this.threadTarget.scrollTop = this.threadTarget.scrollHeight
    } catch (err) {
      this.threadTarget.innerHTML = '<p class="text-theme-secondary text-sm">Failed to load messages.</p>'
    }
  }

  appendMessage(m) {
    const isMe = m.sender_id === this.currentUserIdValue
    const div = document.createElement("div")
    div.className = `flex ${isMe ? "justify-end" : "justify-start"}`
    div.innerHTML = `
      <div class="max-w-[80%] rounded-lg px-3 py-2 ${isMe ? "bg-theme-accent text-white" : "bg-theme-secondary text-theme-primary"}">
        <div class="text-sm whitespace-pre-wrap break-words">${this.escapeHtml(m.content)}</div>
        <div class="text-xs mt-1 opacity-80">${this.formatTime(m.created_at)}</div>
      </div>
    `
    this.threadTarget.appendChild(div)
  }

  formatTime(iso) {
    if (!iso) return ""
    const d = new Date(iso)
    const now = new Date()
    const sameDay = d.getDate() === now.getDate() && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
    return sameDay ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : d.toLocaleString()
  }

  onComposerKeydown(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      this.sendMessage()
    }
  }

  insertEmoji(e) {
    const emoji = e.currentTarget.dataset.emoji
    if (!emoji || !this.hasComposerTarget) return
    const ta = this.composerTarget
    const start = ta.selectionStart
    const end = ta.selectionEnd
    const before = ta.value.slice(0, start)
    const after = ta.value.slice(end)
    ta.value = before + emoji + after
    ta.selectionStart = ta.selectionEnd = start + emoji.length
    ta.focus()
    this.updateCharCount()
  }

  updateCharCount() {
    if (!this.hasComposerTarget || !this.hasCharCountTarget) return
    const len = this.composerTarget.value.length
    this.charCountTarget.textContent = `${len} / 4000`
  }

  async sendMessage() {
    if (!this.selectedRecipient || !this.hasComposerTarget) return
    const content = this.composerTarget.value.trim()
    if (!content) return
    const btn = this.sendBtnTarget
    const origText = btn.textContent
    btn.disabled = true
    btn.textContent = "Sending..."
    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content
      const resp = await fetch(this.sendUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrf || "",
          "X-Requested-With": "XMLHttpRequest"
        },
        body: JSON.stringify({ recipient_id: this.selectedRecipient.id, content })
      })
      const data = await resp.json().catch(() => ({}))
      if (resp.ok && data.id) {
        this.appendMessage({ sender_id: this.currentUserIdValue, content, created_at: data.created_at })
        this.composerTarget.value = ""
        this.updateCharCount()
        this.threadTarget.scrollTop = this.threadTarget.scrollHeight
      } else {
        window.showToast('error', data.error || "Failed to send message.")
      }
    } catch (err) {
      window.showToast('error', "Failed to send message.")
    } finally {
      btn.disabled = false
      btn.textContent = origText
    }
  }

  escapeHtml(s) {
    if (s == null) return ""
    const div = document.createElement("div")
    div.textContent = s
    return div.innerHTML
  }
}
