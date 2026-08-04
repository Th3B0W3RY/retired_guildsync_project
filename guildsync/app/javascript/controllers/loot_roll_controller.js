import { Controller } from "@hotwired/stimulus"
import { getCableConsumer } from "../cable_consumer"

export default class extends Controller {
  static targets = ["totalEntriesLine", "statusBadge", "outcomePanel", "entriesRegion"]

  static values = {
    lootRollId: Number,
    canManage: Boolean,
    forceRerollUrl: String,
    labels: Object
  }

  connect() {
    this.consumer = getCableConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "LootRollsChannel", loot_roll_id: this.lootRollIdValue },
      {
        received: (data) => {
          if (data && data.type === "loot_roll_update") {
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
      this.totalEntriesLineTarget.textContent = this.formatRollCountLine(data.total_entries)
    }
    if (this.hasStatusBadgeTarget) {
      this.updateStatusBadge(data)
    }
    if (this.hasOutcomePanelTarget) {
      this.outcomePanelTarget.innerHTML = this.buildOutcomeHtml(data)
    }
    if (this.hasEntriesRegionTarget) {
      this.entriesRegionTarget.innerHTML = this.buildEntriesRegionHtml(data)
    }
  }

  formatRollCountLine(count) {
    const n = Number(count) || 0
    const L = this.labelsValue
    let word
    if (n === 0) word = L.roll_word_zero
    else if (n === 1) word = L.roll_word_one
    else word = L.roll_word_other
    return `${n} ${word}`
  }

  updateStatusBadge(data) {
    const el = this.statusBadgeTarget
    const L = this.labelsValue
    const showOpen =
      typeof data.currently_open === "boolean" ? data.currently_open : data.status !== "closed"
    el.textContent = showOpen ? L.open : L.closed
    el.classList.remove(
      "bg-green-900/30",
      "text-green-500",
      "bg-gray-900/30",
      "text-gray-500"
    )
    if (showOpen) {
      el.classList.add("bg-green-900/30", "text-green-500")
    } else {
      el.classList.add("bg-gray-900/30", "text-gray-500")
    }
  }

  buildOutcomeHtml(data) {
    const L = this.labelsValue
    const entries = data.entries || []
    const highest =
      entries.length > 0 ? Math.max(...entries.map((e) => Number(e.roll_value))) : null

    if (data.has_tie && highest != null) {
      const tiedNames = entries
        .filter((e) => Number(e.roll_value) === highest)
        .map((e) => e.display_name)
        .join(", ")
      return `
        <div class="mb-6 p-4 bg-orange-900/20 border border-orange-500 rounded-lg">
          <div class="flex items-center gap-3">
            <svg class="w-8 h-8 text-orange-500" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
            </svg>
            <div>
              <h3 class="text-lg font-bold text-orange-500">${this.escapeHtml(L.tie_detected)}</h3>
              <p class="text-theme-primary">
                <span class="font-semibold">${this.escapeHtml(tiedNames)}</span> ${this.escapeHtml(L.are_tied_at)} <span class="font-bold text-xl">${highest}</span>
              </p>
              <p class="text-sm text-theme-secondary mt-1">${this.escapeHtml(L.tied_reroll_hint)}</p>
            </div>
          </div>
        </div>`
    }

    const winnerId = data.winner_id
    if (winnerId != null) {
      const winner = entries.find((e) => Number(e.id) === Number(winnerId))
      if (winner) {
        return `
          <div class="mb-6 p-4 bg-yellow-900/20 border border-yellow-500 rounded-lg">
            <div class="flex items-center gap-3">
              <svg class="w-8 h-8 text-yellow-500" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
                <path fill-rule="evenodd" d="M5 2a2 2 0 00-2 2v14l3.5-2 3.5 2 3.5-2 3.5 2V4a2 2 0 00-2-2H5zm4.707 5.707a1 1 0 00-1.414-1.414l-3 3a1 1 0 000 1.414l3 3a1 1 0 001.414-1.414L8.414 11H12a1 1 0 100-2H8.414l1.293-1.293z" clip-rule="evenodd"></path>
              </svg>
              <div>
                <h3 class="text-lg font-bold text-yellow-500">${this.escapeHtml(L.winner)}</h3>
                <p class="text-theme-primary">
                  <span class="font-semibold">${this.escapeHtml(winner.display_name)}</span> ${this.escapeHtml(L.with_roll_of)} <span class="font-bold text-xl">${this.escapeHtml(String(winner.roll_value))}</span>
                </p>
              </div>
            </div>
          </div>`
      }
    }

    return ""
  }

  buildEntriesRegionHtml(data) {
    const L = this.labelsValue
    const entries = data.entries || []
    if (entries.length === 0) {
      return `<p class="text-theme-secondary">${this.escapeHtml(L.no_rolls_yet)}</p>`
    }

    const highest =
      entries.length > 0 ? Math.max(...entries.map((e) => Number(e.roll_value))) : null
    const hasTie = data.has_tie === true
    const token = document.querySelector('meta[name="csrf-token"]')?.content || ""

    const rows = entries
      .map((entry, index) => {
        const isWinner = entry.is_winner === true
        const isTied = hasTie && Number(entry.roll_value) === highest
        const rowBg = isWinner
          ? "bg-yellow-900/20 border border-yellow-500"
          : isTied
            ? "bg-orange-900/20 border border-orange-500"
            : "bg-theme-primary"

        const rankInner = isTied ? "⚠️" : String(index + 1)
        let rankCircle
        if (isTied) {
          rankCircle = "bg-orange-500 text-white"
        } else if (index === 0) {
          rankCircle = "bg-yellow-500 text-black"
        } else if (index === 1) {
          rankCircle = "bg-gray-400 text-black"
        } else if (index === 2) {
          rankCircle = "bg-amber-700 text-white"
        } else {
          rankCircle = "bg-theme-secondary text-theme-primary"
        }

        const rollClass = isWinner
          ? "text-yellow-500"
          : isTied
            ? "text-orange-500"
            : "text-theme-accent"

        let reroll = ""
        if (this.canManageValue && !hasTie && token) {
          const confirmMsg = L.force_reroll_confirm.replace(/___NAME___/g, entry.display_name)
          const action = `${this.forceRerollUrlValue}?entry_id=${encodeURIComponent(entry.id)}`
          reroll = `
            <form action="${this.escapeAttr(action)}" method="post" class="inline" data-turbo="false">
              <input type="hidden" name="authenticity_token" value="${this.escapeAttr(token)}" />
              <button type="submit" class="px-3 py-1 bg-orange-600 text-white rounded text-sm hover:bg-orange-700 transition-colors"
                data-turbo="false"
                onclick="return confirm(${JSON.stringify(confirmMsg)})">
                ${this.escapeHtml(L.force_reroll)}
              </button>
            </form>`
        }

        const tiedBadge = isTied
          ? `<span class="ml-2 px-2 py-0.5 bg-orange-500 text-white text-xs rounded">${this.escapeHtml(L.tied)}</span>`
          : ""

        return `
          <div class="flex items-center justify-between p-3 rounded-lg ${rowBg}">
            <div class="flex items-center gap-3">
              <span class="w-8 h-8 flex items-center justify-center rounded-full ${rankCircle} font-bold">${rankInner}</span>
              <span class="text-theme-primary font-medium">
                ${this.escapeHtml(entry.display_name)}
                ${tiedBadge}
              </span>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-2xl font-bold ${rollClass}">${this.escapeHtml(String(entry.roll_value))}</span>
              ${reroll}
            </div>
          </div>`
      })
      .join("")

    return `<div class="space-y-2">${rows}</div>`
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
