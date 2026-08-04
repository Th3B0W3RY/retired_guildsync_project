import { Controller } from "@hotwired/stimulus"
import { getCableConsumer } from "../cable_consumer"

export default class extends Controller {
  static targets = ["yesButton", "noButton", "maybeButton"]

  static values = {
    pollId: Number,
    voteUrl: String
  }

  connect() {
    this.consumer = getCableConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "PollsChannel",
        poll_id: this.pollIdValue
      },
      {
        received: (data) => {
          if (data.type === 'vote_update') {
            this.updateResults(data.vote_counts, data.vote_percentages, null)
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
    const choice = event.currentTarget.dataset.choice
    const url = this.voteUrlValue

    // Disable buttons during request
    this.disableButtons()

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ choice: parseInt(choice) })
      })

      const data = await response.json()

      if (data.success) {
        // Update UI with new vote counts
        this.updateResults(data.vote_counts, data.vote_percentages, parseInt(choice))
      } else {
        window.showToast('error', data.error || 'Failed to vote')
      }
    } catch (error) {
      console.error('Vote error:', error)
      window.showToast('error', 'An error occurred while voting. Please try again.')
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

  updateResults(voteCounts, votePercentages, userChoice) {
    // Update vote counts and percentages in the results section
    const yesCount = document.querySelector('[data-vote-type="yes"] .vote-count')
    const noCount = document.querySelector('[data-vote-type="no"] .vote-count')
    const maybeCount = document.querySelector('[data-vote-type="maybe"] .vote-count')

    const yesPercent = document.querySelector('[data-vote-type="yes"] .vote-percent')
    const noPercent = document.querySelector('[data-vote-type="no"] .vote-percent')
    const maybePercent = document.querySelector('[data-vote-type="maybe"] .vote-percent')

    const yesBar = document.querySelector('[data-vote-type="yes"] .vote-bar')
    const noBar = document.querySelector('[data-vote-type="no"] .vote-bar')
    const maybeBar = document.querySelector('[data-vote-type="maybe"] .vote-bar')

    if (yesCount) yesCount.textContent = `${voteCounts.yes} votes`
    if (noCount) noCount.textContent = `${voteCounts.no} votes`
    if (maybeCount) maybeCount.textContent = `${voteCounts.maybe} votes`

    if (yesPercent) yesPercent.textContent = `(${votePercentages.yes}%)`
    if (noPercent) noPercent.textContent = `(${votePercentages.no}%)`
    if (maybePercent) maybePercent.textContent = `(${votePercentages.maybe}%)`

    if (yesBar) yesBar.style.width = `${votePercentages.yes}%`
    if (noBar) noBar.style.width = `${votePercentages.no}%`
    if (maybeBar) maybeBar.style.width = `${votePercentages.maybe}%`

    // Update button highlights
    this.yesButtonTarget.classList.remove('ring-2', 'ring-green-400')
    this.noButtonTarget.classList.remove('ring-2', 'ring-red-400')
    this.maybeButtonTarget.classList.remove('ring-2', 'ring-yellow-400')

    if (userChoice === 0) {
      this.yesButtonTarget.classList.add('ring-2', 'ring-green-400')
    } else if (userChoice === 1) {
      this.noButtonTarget.classList.add('ring-2', 'ring-red-400')
    } else if (userChoice === 2) {
      this.maybeButtonTarget.classList.add('ring-2', 'ring-yellow-400')
    }
  }
}

