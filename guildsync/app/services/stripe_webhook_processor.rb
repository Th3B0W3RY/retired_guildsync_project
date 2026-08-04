# frozen_string_literal: true

# Processes a verified Stripe::Event after idempotency claim. Raises on failure so the
# controller can delete the idempotency row and allow Stripe retries.
class StripeWebhookProcessor
  def self.call(event)
    new(event).call
  end

  def initialize(event)
    @event = event
  end

  def call
    case @event.type
    when "customer.subscription.created",
         "customer.subscription.updated",
         "customer.subscription.pending_update_applied"
      sync_subscription(@event.data.object)
    when "customer.subscription.deleted"
      handle_subscription_deleted(@event.data.object)
    when "invoice.payment_succeeded"
      handle_invoice_payment_succeeded(@event.data.object)
    when "invoice.payment_failed"
      handle_invoice_payment_failed(@event.data.object)
    end
  end

  private

  def sync_subscription(stripe_sub)
    user = User.find_by(stripe_customer_id: stripe_sub.customer)
    unless user
      Rails.logger.warn "Stripe webhook: no user for customer #{stripe_sub.customer}"
      log_billing_failure("billing.subscription_update", reason: "user_not_found")
      return
    end

    price_id = stripe_sub.items.data.first&.price&.id
    pricing_plan = PricingPlan.find_by_effective_stripe_price(price_id) if price_id
    plan_slug = (pricing_plan&.name || "Free").to_s.downcase

    user.update_columns(
      stripe_subscription_id: stripe_sub.id,
      plan: plan_slug
    )

    subscription_record = user.subscriptions.find_or_initialize_by(stripe_subscription_id: stripe_sub.id)

    status_map = {
      "active" => :active,
      "trialing" => :trialing,
      "past_due" => :active,
      "canceled" => :canceled,
      "unpaid" => :canceled,
      "incomplete" => :active,
      "incomplete_expired" => :canceled
    }
    mapped_status = status_map[stripe_sub.status] || :active

    trial_ends_at = if stripe_sub.trial_end
      Time.zone.at(stripe_sub.trial_end)
    else
      subscription_record.trial_ends_at
    end

    subscription_record.assign_attributes(
      pricing_plan: pricing_plan || user.current_subscription&.pricing_plan || PricingPlan.find_by(name: "Free"),
      stripe_customer_id: stripe_sub.customer,
      status: mapped_status,
      started_at: Time.zone.at(stripe_sub.current_period_start),
      expires_at: nil,
      trial_ends_at: trial_ends_at,
      stripe_price_id: price_id.presence || subscription_record.stripe_price_id
    )
    subscription_record.save!

    if pricing_plan&.name.to_s.strip.casecmp?("elite")
      user.update_columns(beta_features_enabled: true)
    end

    Rails.logger.info "Stripe webhook: updated user #{user.id} subscription #{stripe_sub.id}"
    log_billing_success("billing.subscription_update", user, subscription_id: stripe_sub.id, status: stripe_sub.status)
  end

  def handle_subscription_deleted(stripe_sub)
    user = User.find_by(stripe_customer_id: stripe_sub.customer)
    unless user
      Rails.logger.warn "Stripe webhook: no user for customer #{stripe_sub.customer}"
      log_billing_failure("billing.subscription_deleted", reason: "user_not_found")
      return
    end

    user.update_columns(plan: "free", stripe_subscription_id: nil)

    subscription_record = user.subscriptions.find_by(stripe_subscription_id: stripe_sub.id)
    subscription_record&.update!(status: :canceled, canceled_at: Time.current)

    user.activate_free_plan!

    Rails.logger.info "Stripe webhook: deleted subscription for user #{user.id}"
    log_billing_success("billing.subscription_deleted", user, subscription_id: stripe_sub.id)
  end

  def handle_invoice_payment_succeeded(invoice)
    user = User.find_by(stripe_customer_id: invoice.customer)
    return unless user && invoice.subscription.present?

    subscription = user.subscriptions.find_by(stripe_subscription_id: invoice.subscription)
    return unless subscription

    amount_paid = invoice.amount_paid.to_i
    if amount_paid.positive? && subscription.first_paid_invoice_at.blank?
      subscription.update_columns(first_paid_invoice_at: Time.zone.at(invoice.created))
    end

    update_params = { status: :active }
    update_params[:started_at] = Time.zone.at(invoice.period_start) if invoice.period_start
    subscription.update!(update_params)

    log_billing_success("billing.invoice_payment_succeeded", user, subscription_id: invoice.subscription)
  end

  def handle_invoice_payment_failed(invoice)
    user = User.find_by(stripe_customer_id: invoice.customer)
    return unless user && invoice.subscription.present?

    subscription = user.subscriptions.find_by(stripe_subscription_id: invoice.subscription)
    return unless subscription

    Rails.logger.warn "Stripe webhook: payment failed user #{user.id} subscription #{invoice.subscription}"
    log_billing_failure(
      "billing.invoice_payment_failed",
      user: user,
      subscription_id: invoice.subscription
    )
  end

  def log_billing_success(event_name, user, metadata = {})
    SecurityAuditLogger.log(
      event: event_name,
      status: "success",
      actor: nil,
      subject: user,
      request: nil,
      metadata: metadata
    )
  end

  def log_billing_failure(event_name, reason: nil, user: nil, **metadata)
    SecurityAuditLogger.log(
      event: event_name,
      status: "failure",
      actor: nil,
      subject: user,
      request: nil,
      metadata: metadata.merge(reason: reason).compact
    )
  end
end
