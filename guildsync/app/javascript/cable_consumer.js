import { createConsumer } from "@rails/actioncable"

let sharedConsumer = null

/**
 * One Action Cable WebSocket per browser tab. Stimulus controllers should call
 * subscription.unsubscribe() in disconnect() only — never disconnect the shared consumer.
 */
export function getCableConsumer() {
  if (!sharedConsumer) {
    sharedConsumer = createConsumer()
  }
  return sharedConsumer
}
