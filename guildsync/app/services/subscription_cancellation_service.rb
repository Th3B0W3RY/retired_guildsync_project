# frozen_string_literal: true

class SubscriptionCancellationService
  Result = Struct.new(:ok, :error, :mode, keyword_init: true)

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    sub = @user.current_subscription
    return failure("No subscription to cancel.") unless sub

    if sub.stripe_subscription_id.blank?
      sub.cancel!
      return Result.new(ok: true, error: nil, mode: :local)
    end

    stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id)

    if sub.first_paid_invoice_at.blank?
      Stripe::Subscription.cancel(stripe_sub.id)
      return Result.new(ok: true, error: nil, mode: :immediate_no_payment)
    end

    if sub.refund_eligible?
      refund_paid_invoices_in_policy_window(sub, stripe_sub.id)
      Stripe::Subscription.cancel(stripe_sub.id)
      Result.new(ok: true, error: nil, mode: :refund_and_cancel)
    else
      Stripe::Subscription.update(stripe_sub.id, { cancel_at_period_end: true })
      Result.new(ok: true, error: nil, mode: :period_end)
    end
  rescue Stripe::StripeError => e
    failure(e.message)
  end

  def self.resume!(user:)
    sub = user.current_subscription
    return Result.new(ok: false, error: "No subscription.", mode: nil) if sub.blank? || sub.stripe_subscription_id.blank?

    Stripe::Subscription.update(sub.stripe_subscription_id, { cancel_at_period_end: false })
    Result.new(ok: true, error: nil, mode: :resumed)
  rescue Stripe::StripeError => e
    Result.new(ok: false, error: e.message, mode: nil)
  end

  private

  def failure(message)
    Result.new(ok: false, error: message, mode: nil)
  end

  def refund_paid_invoices_in_policy_window(subscription_record, stripe_subscription_id)
    start_at = subscription_record.first_paid_invoice_at
    deadline = start_at + Subscription::REFUND_POLICY_WINDOW

    invoices = Stripe::Invoice.list(subscription: stripe_subscription_id, status: "paid", limit: 100)
    invoices.auto_paging_each do |inv|
      next if inv.amount_paid.to_i <= 0

      created = Time.zone.at(inv.created)
      next if created < start_at || created > deadline

      refund_invoice_payment(inv)
    end
  end

  def refund_invoice_payment(inv)
    pi = inv.respond_to?(:payment_intent) ? inv.payment_intent : nil
    pi_id = pi.is_a?(String) ? pi : pi&.id
    if pi_id.present?
      Stripe::Refund.create(payment_intent: pi_id)
      return
    end

    ch = inv.respond_to?(:charge) ? inv.charge : nil
    ch_id = ch.is_a?(String) ? ch : ch&.id
    Stripe::Refund.create(charge: ch_id) if ch_id.present?
  rescue Stripe::InvalidRequestError => e
    Rails.logger.warn("SubscriptionCancellationService refund skipped invoice=#{inv.id}: #{e.message}")
  end
end
