# DEPRECATED: This controller is legacy code. 
# New subscriptions should use BillingController#checkout which returns JSON for frontend redirect.
# This controller is kept for backward compatibility but should be removed in the future.
class SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def create
    plan = PricingPlan.find(params[:plan_id])

    # Handle Free plan - no Stripe required
    if plan.name == "Free"
      current_user.activate_free_plan!
      redirect_to upgrade_pricing_path, notice: t('controllers.subscriptions.switched_to_free')
      return
    end

    # Check if plan has Stripe price ID (DB or ENV fallback)
    unless plan.effective_stripe_price_id.present?
      redirect_to pricing_path, alert: t('controllers.subscriptions.not_available')
      return
    end

    # Get or create Stripe customer
    customer_id = current_user.subscriptions
      .where(status: [ :active, :trialing ])
      .order(created_at: :desc)
      .limit(1)
      .pick(:stripe_customer_id)

    session_params = {
      mode: "subscription",
      success_url: success_subscriptions_url + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: pricing_url,
      line_items: [
        {
          price: plan.effective_stripe_price_id,
          quantity: 1
        }
      ],
      metadata: {
        user_id: current_user.id,
        plan_id: plan.id
      },
      subscription_data: begin
        td = Billing::TrialPolicy.stripe_trial_period_days(plan)
        td = nil if current_user.trial_active? && current_user.current_subscription&.pricing_plan_id == plan.id
        h = { metadata: { user_id: current_user.id.to_s, plan_id: plan.id.to_s } }
        h[:trial_period_days] = td if td.present?
        h
      end
    }

    # Only add customer if we have one, otherwise let Stripe create it
    session_params[:customer] = customer_id if customer_id.present?

    session = Stripe::Checkout::Session.create(session_params)

    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error("Stripe error: #{e.class.name}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    redirect_to pricing_path, alert: t('controllers.subscriptions.payment_error', error: e.message)
  rescue => e
    Rails.logger.error("Subscription creation error: #{e.message}")
    redirect_to pricing_path, alert: t('controllers.subscriptions.general_error')
  end

  def success
    session_id = params[:session_id]
    return redirect_to pricing_path, alert: t('controllers.subscriptions.invalid_session') unless session_id

    session = Stripe::Checkout::Session.retrieve(session_id)

    # SECURITY: Validate that the session metadata matches the signed-in user
    # This prevents hijacking where an attacker reuses someone else's session_id
    unless session.metadata && session.metadata.user_id
      Rails.logger.error "Stripe session missing metadata.user_id for session_id: #{session_id}"
      return redirect_to pricing_path, alert: t('controllers.subscriptions.invalid_metadata')
    end

    unless session.metadata.user_id.to_i == current_user.id
      Rails.logger.error "Stripe session user_id mismatch: session.user_id=#{session.metadata.user_id}, current_user.id=#{current_user.id}"
      return redirect_to pricing_path, alert: t('controllers.subscriptions.account_mismatch')
    end

    unless session.metadata.plan_id
      Rails.logger.error "Stripe session missing metadata.plan_id for session_id: #{session_id}"
      return redirect_to pricing_path, alert: t('controllers.subscriptions.invalid_metadata')
    end

    if session.payment_status == "paid"
      stripe_sub = Stripe::Subscription.retrieve(session.subscription)

      # Find or create subscription
      subscription = current_user.subscriptions.find_or_initialize_by(
        stripe_subscription_id: stripe_sub.id
      )

      plan = PricingPlan.find(session.metadata.plan_id)

      subscription.assign_attributes(
        pricing_plan: plan,
        stripe_customer_id: session.customer,
        stripe_subscription_id: stripe_sub.id,
        stripe_price_id: stripe_sub.items.data.first.price.id,
        status: :active,
        started_at: Time.at(stripe_sub.current_period_start),
        expires_at: nil, # Monthly subscriptions don't expire
        trial_ends_at: nil # Trial ended when they subscribed
      )

      subscription.save!

      # Cancel any other active subscriptions
      current_user.subscriptions
        .where.not(id: subscription.id)
        .where(status: [ :active, :trialing ])
        .update_all(status: :canceled, canceled_at: Time.current)

      redirect_to dashboard_path, notice: t('controllers.subscriptions.activated')
    else
      redirect_to pricing_path, alert: t('controllers.subscriptions.payment_not_completed')
    end
  rescue Stripe::StripeError => e
    Rails.logger.error("Stripe error: #{e.message}")
    redirect_to pricing_path, alert: t('controllers.subscriptions.processing_error')
  rescue => e
    Rails.logger.error("Subscription success error: #{e.message}")
    redirect_to pricing_path, alert: t('controllers.subscriptions.success_error')
  end
end
