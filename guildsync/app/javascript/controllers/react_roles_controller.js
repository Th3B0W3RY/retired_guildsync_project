import { Controller } from "@hotwired/stimulus"

// Curated set of Discord-compatible Unicode emoji, grouped by category.
const UNICODE_EMOJIS = [
  // People & expressions
  "😀","😁","😂","🤣","😃","😄","😅","😆","😊","😍","🥰","😎","🤩","🥳","😇","🤗",
  "😤","😠","😡","🤬","😈","👿","💀","☠️","🤡","👻","💩","🙈","🙉","🙊",
  // Hands & gestures
  "👍","👎","👊","✊","🤛","🤜","🤞","✌️","🤟","🤘","👌","🤙","💪","🙌","👏","🤝","👋",
  // Animals
  "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐸","🦄","🐺","🦝","🦔",
  "🦋","🐝","🦅","🦆","🦉","🐺","🦈","🐬","🐳","🦖","🦕",
  // Symbols & objects
  "⭐","🌟","💥","🔥","❄️","🌊","⚡","🌈","☀️","🌙","🌙",
  "❤️","🧡","💛","💚","💙","💜","🖤","🤍","💯","✅","❌","⚠️","🚫","🔒","🔑",
  "🏆","🥇","🎖️","🎗️","🎯","🎲","🎮","🕹️","🃏","🎭","🎨","🎤","🎧","🎵","🎶",
  "⚔️","🛡️","🏹","🗡️","🔱","⚜️","🌀","🔮","💎","👑",
  // Numbers & letters
  "0️⃣","1️⃣","2️⃣","3️⃣","4️⃣","5️⃣","6️⃣","7️⃣","8️⃣","9️⃣","🔟",
  // Miscellaneous
  "🌍","🌎","🌏","🗺️","🏔️","🌋","🏝️","🏜️","🏕️","🏛️","🏗️","🏘️",
]

export default class extends Controller {
  static targets = [
    "channelSelect",
    "slot",
    "roleSelect",
    "emojiButton",
    "emojiDisplay",
    "emojiLabel",
    "emojiName",
    "emojiId",
    "emojiCustom",
    "picker",
    "customEmojis",
    "unicodeEmojis",
    "feedback",
  ]

  static values = {
    guildId: String,
    emojisUrl: String,
  }

  connect() {
    this._customEmojisLoaded = false
    this._activePickerSlot = null
    // Close pickers when clicking outside
    this._outsideClickHandler = this._onOutsideClick.bind(this)
    document.addEventListener("click", this._outsideClickHandler)
    // Populate unicode emoji grids (they are static, render once)
    this._renderUnicodeEmojis()
  }

  disconnect() {
    document.removeEventListener("click", this._outsideClickHandler)
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Emoji picker
  // ──────────────────────────────────────────────────────────────────────────

  togglePicker(event) {
    // Stop the click from bubbling to the document outside-click handler,
    // which would immediately close the picker we're about to open.
    event.stopPropagation()

    const slotEl = event.currentTarget.closest("[data-position]")
    const position = parseInt(slotEl.dataset.position, 10)
    const pickerEl = this._pickerInSlot(position)

    if (!pickerEl) return

    const isOpen = !pickerEl.classList.contains("hidden")

    // Close all pickers first (handles switching between slots)
    this._closeAllPickers()

    if (!isOpen) {
      pickerEl.classList.remove("hidden")
      this._activePickerSlot = position
      if (!this._customEmojisLoaded) {
        this._loadCustomEmojis()
      }
    }
  }

  _onOutsideClick(event) {
    // Close any open picker when the user clicks outside of it.
    // Clicks on the toggle button are stopped at the button (stopPropagation),
    // so they never reach here — we only need to guard against picker content clicks.
    if (!event.target.closest("[data-react-roles-target='picker']")) {
      this._closeAllPickers()
    }
  }

  _closeAllPickers() {
    this.pickerTargets.forEach(p => p.classList.add("hidden"))
    this._activePickerSlot = null
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Emoji selection (called from dynamically-rendered emoji buttons)
  // ──────────────────────────────────────────────────────────────────────────

  _selectEmoji(position, emojiName, emojiId, isCustom, displayText) {
    const slotEl = this._slotByPosition(position)
    if (!slotEl) return

    const displayTarget = slotEl.querySelector("[data-react-roles-target='emojiDisplay']")
    const labelTarget   = slotEl.querySelector("[data-react-roles-target='emojiLabel']")
    const nameTarget    = slotEl.querySelector("[data-react-roles-target='emojiName']")
    const idTarget      = slotEl.querySelector("[data-react-roles-target='emojiId']")
    const customTarget  = slotEl.querySelector("[data-react-roles-target='emojiCustom']")

    if (displayTarget) displayTarget.textContent = displayText
    if (labelTarget)   labelTarget.textContent   = emojiName
    if (nameTarget)    nameTarget.value           = emojiName
    if (idTarget)      idTarget.value             = emojiId || ""
    if (customTarget)  customTarget.value         = isCustom ? "1" : "0"

    this._closeAllPickers()
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Custom emoji loading
  // ──────────────────────────────────────────────────────────────────────────

  async _loadCustomEmojis() {
    try {
      const response = await fetch(this.emojisUrlValue, {
        headers: { "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
      })
      const emojis = await response.json()
      this._customEmojisLoaded = true

      this.customEmojisTargets.forEach(container => {
        container.innerHTML = ""
        if (emojis.length === 0) {
          container.innerHTML = `<span class="text-xs text-theme-secondary">No custom emojis found</span>`
          return
        }
        emojis.forEach(emoji => {
          const position = parseInt(container.closest("[data-position]")?.dataset.position, 10)
          const btn = document.createElement("button")
          btn.type = "button"
          btn.title = emoji.name
          btn.className = "w-7 h-7 hover:bg-theme-secondary rounded cursor-pointer flex items-center justify-center"
          btn.addEventListener("click", (e) => {
            e.stopPropagation()
            this._selectEmoji(
              position,
              emoji.name,
              emoji.id,
              true,
              `<:${emoji.name}:${emoji.id}>`
            )
          })
          const img = document.createElement("img")
          img.src = `https://cdn.discordapp.com/emojis/${emoji.id}.${emoji.animated ? "gif" : "png"}?size=32`
          img.alt = emoji.name
          img.className = "w-6 h-6"
          btn.appendChild(img)
          container.appendChild(btn)
        })
      })
    } catch (e) {
      this.customEmojisTargets.forEach(c => {
        c.innerHTML = `<span class="text-xs text-red-400">Failed to load</span>`
      })
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Unicode emoji rendering
  // ──────────────────────────────────────────────────────────────────────────

  _renderUnicodeEmojis() {
    this.unicodeEmojisTargets.forEach(container => {
      const slotEl = container.closest("[data-position]")
      const position = parseInt(slotEl?.dataset.position, 10)
      container.innerHTML = ""
      UNICODE_EMOJIS.forEach(emoji => {
        const btn = document.createElement("button")
        btn.type = "button"
        btn.textContent = emoji
        btn.className = "text-xl w-8 h-8 hover:bg-theme-secondary rounded cursor-pointer flex items-center justify-center"
        btn.addEventListener("click", (e) => {
          e.stopPropagation()
          this._selectEmoji(position, emoji, null, false, emoji)
        })
        container.appendChild(btn)
      })
    })
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Save configuration via PATCH
  // ──────────────────────────────────────────────────────────────────────────

  async save() {
    const channelId = this.channelSelectTarget.value
    const reactRoles = []

    this.slotTargets.forEach(slot => {
      const position  = parseInt(slot.dataset.position, 10)
      const roleSelect = slot.querySelector("[data-react-roles-target='roleSelect']")
      const emojiNameInput = slot.querySelector("[data-react-roles-target='emojiName']")
      const emojiIdInput   = slot.querySelector("[data-react-roles-target='emojiId']")
      const emojiCustom    = slot.querySelector("[data-react-roles-target='emojiCustom']")

      const roleId   = roleSelect?.value
      const roleName = roleSelect?.selectedOptions[0]?.dataset.roleName || roleId
      const emojiName = emojiNameInput?.value
      const emojiId   = emojiIdInput?.value
      const isCustom  = emojiCustom?.value === "1"

      if (roleId && emojiName) {
        reactRoles.push({ position, role_id: roleId, role_name: roleName, emoji_name: emojiName, emoji_id: emojiId, is_custom_emoji: isCustom })
      }
    })

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/react_roles`, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken || "",
        },
        body: JSON.stringify({ channel_id: channelId, react_roles: reactRoles }),
      })

      const data = await response.json()
      this._showFeedback(data.success ? "success" : "error", data.message || data.error)
    } catch (e) {
      this._showFeedback("error", "Network error — please try again.")
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Feedback banner
  // ──────────────────────────────────────────────────────────────────────────

  _showFeedback(type, message) {
    if (!this.hasFeedbackTarget) return
    const el = this.feedbackTarget
    el.textContent = message
    el.className = [
      "mt-3 text-sm font-medium px-4 py-2 rounded-lg",
      type === "success" ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800",
    ].join(" ")
    el.classList.remove("hidden")
    setTimeout(() => el.classList.add("hidden"), 4000)
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  _slotByPosition(position) {
    return this.slotTargets.find(s => parseInt(s.dataset.position, 10) === position) || null
  }

  _pickerInSlot(position) {
    const slot = this._slotByPosition(position)
    return slot ? slot.querySelector("[data-react-roles-target='picker']") : null
  }
}
