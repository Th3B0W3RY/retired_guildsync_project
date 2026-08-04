import { Controller } from "@hotwired/stimulus"
import { getCableConsumer } from "../cable_consumer"

export default class extends Controller {
  static targets = ["yesButton", "noButton", "maybeButton"]
  static values = {
    voteUrl: String,
    anonymous: Boolean,
    voteNoun: String,
    votesNoun: String,
    pollId: Number
  }

  connect() {
    this.consumer = getCableConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "AlliancePollsChannel",
        alliance_poll_id: this.pollIdValue
      },
      {
        received: (data) => {
          if (data && data.type === "vote_update") {
            this.updateResults({
              vote_counts: data.vote_counts,
              vote_percentages: data.vote_percentages,
              voters_by_choice: data.voters_by_choice
            })
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

  async vote(event) {
    event.preventDefault()
    const choice = parseInt(event.currentTarget.dataset.choice, 10)
    if (Number.isNaN(choice)) return

    this.disableButtons()
    try {
      const response = await fetch(this.voteUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ choice })
      })
      const data = await response.json()

      if (data.success) {
        this.updateResults(data)
        this.setVoteHighlight(data.user_vote)
      } else {
        window.showToast("error", data.error || "Vote failed")
      }
    } catch (err) {
      console.error("Alliance poll vote error:", err)
      window.showToast("error", "An error occurred while voting. Please try again.")
    } finally {
      this.enableButtons()
    }
  }

  disableButtons() {
    this.yesButtonTarget.disabled = true
    this.noButtonTarget.disabled = true
    this.maybeButtonTarget.disabled = true
  }

  enableButtons() {
    this.yesButtonTarget.disabled = false
    this.noButtonTarget.disabled = false
    this.maybeButtonTarget.disabled = false
  }

  setVoteHighlight(userChoice) {
    const buttons = [this.yesButtonTarget, this.noButtonTarget, this.maybeButtonTarget]
    buttons.forEach((btn, i) => {
      const selected = userChoice === i
      btn.classList.toggle("bg-theme-accent", selected)
      btn.classList.toggle("text-white", selected)
      btn.classList.toggle("bg-theme-primary", !selected)
      btn.classList.toggle("text-theme-secondary", !selected)
      btn.classList.toggle("hover:text-theme-accent", !selected)
    })
  }

  updateResults(data) {
    const counts = data.vote_counts || {}
    const pct = data.vote_percentages || {}
    const voters = data.voters_by_choice

    ;["yes", "no", "maybe"].forEach((key) => {
      const col = this.element.querySelector(`[data-ap-vote-type="${key}"]`)
      if (!col) return

      const count = Number(counts[key] ?? 0)
      const p = Number(pct[key] ?? 0)

      const numEl = col.querySelector(".ap-vote-count-num")
      const nounEl = col.querySelector(".ap-vote-count-noun")
      const pctEl = col.querySelector(".ap-vote-percent")
      const barEl = col.querySelector(".ap-vote-bar")
      const voterBlock = col.querySelector(".ap-voter-block")
      const namesEl = col.querySelector(".ap-voter-names")

      if (numEl) numEl.textContent = String(count)
      if (nounEl) nounEl.textContent = count === 1 ? this.voteNounValue : this.votesNounValue
      if (pctEl) pctEl.textContent = `${p}%`
      if (barEl) barEl.style.width = `${p}%`

      if (!this.anonymousValue && voterBlock && namesEl && voters && Object.prototype.hasOwnProperty.call(voters, key)) {
        const list = voters[key] || []
        if (list.length === 0) {
          voterBlock.classList.add("hidden")
          namesEl.textContent = ""
        } else {
          voterBlock.classList.remove("hidden")
          namesEl.textContent = list.join(", ")
        }
      }
    })
  }
}
