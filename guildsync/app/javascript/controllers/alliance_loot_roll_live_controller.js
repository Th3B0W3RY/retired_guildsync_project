import { Controller } from "@hotwired/stimulus"
import { getCableConsumer } from "../cable_consumer"

export default class extends Controller {
  static targets = ["totalEntriesLine", "statusBadge", "winnerPanel", "entriesRegion", "actionsRow"]

  static values = {
    allianceLootRollId: Number,
    currentUserId: Number,
    anonymous: Boolean,
    canManageClose: Boolean,
    enterUrl: String,
    closeUrl: String,
    labels: Object
  }

  connect() {
    this.consumer = getCableConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "AllianceLootRollsChannel", alliance_loot_roll_id: this.allianceLootRollIdValue },
      {
        received: (data) => {
          if (data && data.type === "alliance_loot_roll_update") {
            this.applyUpdate(data)
          }
        }
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  applyUpdate(data) {
    if (this.hasTotalEntriesLineTarget) {
      this.totalEntriesLineTarget.textContent = this.formatEntriesLine(data.total_entries)
    }
    if (this.hasStatusBadgeTarget) {
      this.updateStatusBadge(data)
    }
    if (this.hasWinnerPanelTarget) {
      this.winnerPanelTarget.innerHTML = this.buildWinnerHtml(data)
    }
    if (this.hasEntriesRegionTarget) {
      this.entriesRegionTarget.innerHTML = this.buildEntriesRegionHtml(data)
    }
    if (this.hasActionsRowTarget && !this.anonymousValue) {
      this.actionsRowTarget.innerHTML = this.buildActionsHtml(data)
    }
  }

  formatEntriesLine(count) {
    const n = Number(count) || 0
    const lang = (document.documentElement.lang || "en").split("-")[0]
    const pr = new Intl.PluralRules(lang).select(n)
    const words = this.labelsValue.entries_line_words || {}
    const tpl =
      words[pr] || words.other || words.many || words.few || words.two || words.one || words.zero || String(n)
    return tpl.replace(/%\{count\}/g, String(n))
  }

  updateStatusBadge(data) {
    const showOpen =
      typeof data.currently_open === "boolean" ? data.currently_open : data.status !== "closed"
    const el = this.statusBadgeTarget
    const L = this.labelsValue
    el.textContent = showOpen ? L.open : L.closed
    el.classList.remove("bg-green-900/30", "text-green-400", "bg-gray-900/30", "text-gray-500")
    if (showOpen) {
      el.classList.add("bg-green-900/30", "text-green-400")
    } else {
      el.classList.add("bg-gray-900/30", "text-gray-500")
    }
  }

  buildWinnerHtml(data) {
    const L = this.labelsValue
    const wid = data.winner_id
    if (wid == null) return ""

    const entries = data.entries || []
    const w = entries.find((e) => Number(e.id) === Number(wid))
    if (!w) return ""

    const nameShown = w.mask_name ? L.anonymous_entry : w.display_name
    const line = L.winner_line
      .split("___NAME___")
      .join(this.escapeHtml(nameShown))
      .split("___ROLL___")
      .join(this.escapeHtml(String(w.roll_value)))

    return `<div class="mt-4 p-4 bg-yellow-900/20 border border-yellow-500/30 rounded-lg"><p class="text-yellow-300 font-semibold">${line}</p></div>`
  }

  buildEntriesRegionHtml(data) {
    const L = this.labelsValue
    const entries = data.entries || []
    if (entries.length === 0) {
      return `<p class="text-theme-secondary">${this.escapeHtml(L.no_entries)}</p>`
    }

    const rows = entries
      .map((entry, idx) => {
        const isWinner = entry.is_winner === true
        const name = entry.mask_name ? L.anonymous_entry : entry.display_name
        const rowBg = isWinner ? "bg-yellow-900/20 border border-yellow-500/30" : "bg-theme-primary"
        const rollCls = isWinner ? "text-yellow-400" : "text-theme-accent"
        return `
          <div class="flex items-center justify-between py-2 px-3 rounded-lg ${rowBg}">
            <div class="flex items-center gap-3">
              <span class="text-theme-secondary text-sm">#${idx + 1}</span>
              <span class="text-theme-primary">${this.escapeHtml(name)}</span>
            </div>
            <span class="text-2xl font-bold ${rollCls}">${this.escapeHtml(String(entry.roll_value))}</span>
          </div>`
      })
      .join("")

    return `<div class="space-y-2">${rows}</div>`
  }

  buildActionsHtml(data) {
    const L = this.labelsValue
    const token = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const open = data.currently_open === true
    let html = '<div class="mt-4 flex gap-3">'

    if (open && token) {
      const myEntry = (data.entries || []).find(
        (e) => e.user_id != null && Number(e.user_id) === Number(this.currentUserIdValue)
      )
      if (!myEntry) {
        html += `<form action="${this.escapeAttr(this.enterUrlValue)}" method="post" class="inline" data-turbo="false">
          <input type="hidden" name="authenticity_token" value="${this.escapeAttr(token)}" />
          <button type="submit" class="px-6 py-2 bg-theme-accent text-white rounded-lg hover:bg-theme-accent-hover transition-colors font-semibold">${this.escapeHtml(L.enter)}</button>
        </form>`
      } else {
        const line = L.your_roll_line.split("___ROLL___").join(this.escapeHtml(String(myEntry.roll_value)))
        html += `<div class="px-6 py-2 bg-green-900/30 text-green-400 rounded-lg font-medium">${line}</div>`
      }
    }

    if (open && this.canManageCloseValue && token) {
      html += `<form action="${this.escapeAttr(this.closeUrlValue)}" method="post" class="inline" data-turbo="false">
        <input type="hidden" name="authenticity_token" value="${this.escapeAttr(token)}" />
        <button type="submit" class="px-6 py-2 bg-yellow-600 text-white rounded-lg hover:bg-yellow-700 transition-colors font-semibold" data-turbo="false"
          onclick="return confirm(${JSON.stringify(L.close_confirm)})">${this.escapeHtml(L.close)}</button>
      </form>`
    }

    html += "</div>"
    return html
  }

  escapeHtml(str) {
    if (str == null) return ""
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  escapeAttr(str) {
    return this.escapeHtml(str).replace(/'/g, "&#39;")
  }
}
