# frozen_string_literal: true

class SubscriptionPlanPreviewService
  def self.call(user:, target_plan:, interval: "month")
    billing_interval = interval.to_s == "year" ? "year" : "month"
    sub = user.current_subscription
    return nil if sub.blank? || sub.stripe_subscription_id.blank?

    new_price_id = target_plan.price_id_for_interval(billing_interval)
    return nil if new_price_id.blank?

    stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id)
    item = stripe_sub.items.data.first
    return nil unless item

    current_plan = sub.pricing_plan
    proration = SubscriptionPlanChangeService.proration_behavior_between(current_plan, target_plan)

    inv = Stripe::Invoice.upcoming(
      customer: stripe_sub.customer,
      subscription: stripe_sub.id,
      subscription_items: [ { id: item.id, price: new_price_id } ],
      subscription_proration_behavior: proration
    )

    {
      amount_due: inv.amount_due,
      currency: inv.currency
    }
  rescue Stripe::StripeError => e
    Rails.logger.warn("SubscriptionPlanPreviewService: #{e.message}")
    nil
  end
end
