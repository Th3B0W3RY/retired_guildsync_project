import { Controller } from "@hotwired/stimulus"
import { getCableConsumer } from "../cable_consumer"

export default class extends Controller {
  static values = {
    allianceId: Number,
    messageType: String
  }

  connect() {
    this.consumer = getCableConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "AllianceMessagesChannel",
        alliance_id: this.allianceIdValue,
        message_type: this.messageTypeValue
      },
      {
        connected: () => {
          this.dispatch("connected", { bubbles: true })
        },
        disconnected: () => {
          this.dispatch("disconnected", { bubbles: true })
        },
        received: (data) => {
          if (data && data.type === "message" && data.message) {
            this.dispatch("message", { detail: { message: data.message }, bubbles: true })
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
}
