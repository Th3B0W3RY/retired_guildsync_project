# app/controllers/stripe/webhooks_controller.rb
module Stripe
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!
    skip_before_action :ensure_fully_authenticated

    def receive
      payload = request.body.read
      sig = request.env["HTTP_STRIPE_SIGNATURE"]
      secret = ENV["STRIPE_WEBHOOK_SECRET"]

      unless secret
        GuildsyncLoggers.error(GuildsyncLoggers.stripe_webhook_errors, "STRIPE_WEBHOOK_SECRET is not set - signature verification impossible")
        Rails.logger.error "Signature verification failed: STRIPE_WEBHOOK_SECRET is not set"
        return head :unauthorized
      end

      Rails.logger.info "🔥 Stripe webhook received"

      begin
        event = ::Stripe::Webhook.construct_event(payload, sig, secret)
      rescue JSON::ParserError => e
        GuildsyncLoggers.log_exception(GuildsyncLoggers.stripe_webhook_errors, e, payload_preview: payload.to_s[0..200])
        Rails.logger.error "Invalid JSON: #{e.message}"
        return head :bad_request
      rescue ::Stripe::SignatureVerificationError => e
        GuildsyncLoggers.log_exception(GuildsyncLoggers.stripe_webhook_errors, e, reason: "Signature verification failed - wrong secret or payload tampering")
        Rails.logger.error "Signature verification failed: #{e.message}"
        return head :unauthorized
      end

      Rails.logger.info "Event verified: #{event['type']}"
      log_security_event(
        event: "stripe.webhook_received",
        status: "success",
        actor: nil,
        metadata: { event_type: event.type }
      )

      begin
        ::StripeWebhookEvent.create!(
          stripe_event_id: event.id,
          event_type: event.type,
          processed_at: Time.current
        )
      rescue ActiveRecord::RecordNotUnique
        return head :ok
      rescue ActiveRecord::RecordInvalid => e
        taken = e.record.errors.details[:stripe_event_id]&.any? { |err| err[:error] == :taken }
        return head :ok if taken
        raise
      end

      begin
        ::StripeWebhookProcessor.call(event)
      rescue StandardError => e
        ::StripeWebhookEvent.where(stripe_event_id: event.id).delete_all
        raise e
      end

      head :ok
    rescue StandardError => e
      log_security_event(
        event: "stripe.webhook_received",
        status: "error",
        actor: nil,
        metadata: { event_type: event&.type, error_class: e.class.name }
      )
      GuildsyncLoggers.log_exception(GuildsyncLoggers.stripe_webhook_errors, e, event_type: event&.type, path: request.path)
      Rails.logger.error "Stripe webhook error: #{e.message}"
      raise
    end
  end
end
