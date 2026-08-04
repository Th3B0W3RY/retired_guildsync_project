# frozen_string_literal: true

class SubscriptionPlanChangeService
  Result = Struct.new(:ok, :error, keyword_init: true)

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def self.proration_behavior_between(from_plan, to_plan)
    if to_plan.display_order > from_plan.display_order
      "always_invoice"
    elsif to_plan.display_order < from_plan.display_order
      "create_prorations"
    else
      "always_invoice"
    end
  end

  def initialize(user:, target_plan:, interval: "month")
    @user = user
    @target_plan = target_plan
    @interval = interval.to_s == "year" ? "year" : "month"
  end

  def call
    sub = @user.current_subscription
    return failure("No active subscription.") unless sub
    return failure("Select a paid plan.") if @target_plan.name.to_s == "Free"
    return failure("No Stripe subscription on file. Complete checkout first.") if sub.stripe_subscription_id.blank?

    new_price_id = @target_plan.price_id_for_interval(@interval)
    return failure("That billing interval is not available for this plan.") if new_price_id.blank?

    stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id)
    return failure(subscription_state_error(stripe_sub)) unless allowed_stripe_status?(stripe_sub)

    item = stripe_sub.items.data.first
    return failure("Subscription has no line items.") unless item

    current_plan = sub.pricing_plan
    if current_plan.id == @target_plan.id && item.price.id == new_price_id
      return failure("You are already on this plan and billing interval.")
    end

    proration = self.class.proration_behavior_between(current_plan, @target_plan)

    Stripe::Subscription.update(
      stripe_sub.id,
      {
        items: [ { id: item.id, price: new_price_id } ],
        proration_behavior: proration,
        payment_behavior: "error_if_incomplete"
      }
    )

    Result.new(ok: true, error: nil)
  rescue Stripe::StripeError => e
    failure(e.message)
  end

  private

  def failure(message)
    Result.new(ok: false, error: message)
  end

  def allowed_stripe_status?(stripe_sub)
    %w[active trialing].include?(stripe_sub.status)
  end

  def subscription_state_error(stripe_sub)
    case stripe_sub.status
    when "past_due", "unpaid"
      "Update your payment method in the billing portal before changing plans."
    when "canceled", "incomplete_expired"
      "This subscription can no longer be changed. Start a new subscription from pricing."
    when "incomplete"
      "Complete payment setup before changing plans."
    else
      "Subscription cannot be changed in its current state."
    end
  end

end
