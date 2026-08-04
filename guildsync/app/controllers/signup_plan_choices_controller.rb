# frozen_string_literal: true

# After sign-up with Upgraded/Elite selected (no Basic trial on those plans), user completes MFA then lands here:
# choose Basic trial or continue to Stripe checkout for the originally selected paid tier.
class SignupPlanChoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :load_pending_plan

  def show
    return redirect_to dashboard_path if @pending_plan.blank?
  end

  def choose_basic_trial
    return redirect_to dashboard_path if @pending_plan.blank?

    basic = PricingPlan.find_by("LOWER(TRIM(name)) = ?", "basic")
    unless basic
      redirect_to upgrade_pricing_path, alert: t("signup_plan_choices.missing_basic")
      return
    end

    session.delete(:post_signup_paid_plan_id)
    if current_user.can_start_trial?
      current_user.start_trial_from_free!(basic)
      redirect_to dashboard_path, notice: t("signup_plan_choices.basic_trial_started")
    else
      redirect_to upgrade_pricing_path, alert: t("signup_plan_choices.trial_unavailable")
    end
  end

  def choose_paid_plan
    return redirect_to dashboard_path if @pending_plan.blank?

    plan = @pending_plan
    session.delete(:post_signup_paid_plan_id)

    unless plan.effective_stripe_price_id.present?
      redirect_to upgrade_pricing_path, alert: t("controllers.pricing.not_available")
      return
    end

    begin
      customer_id = current_user.stripe_customer_id
      unless customer_id
        customer = Stripe::Customer.create(email: current_user.email)
        current_user.update!(stripe_customer_id: customer.id)
        customer_id = customer.id
      end

      trial_days = Billing::TrialPolicy.stripe_trial_period_days(plan)
      sub_data = {
        metadata: {
          user_id: current_user.id.to_s,
          plan_id: plan.id.to_s
        }
      }
      sub_data[:trial_period_days] = trial_days if trial_days.present?

      session = Stripe::Checkout::Session.create(
        customer: customer_id,
        mode: "subscription",
        line_items: [{ price: plan.effective_stripe_price_id, quantity: 1 }],
        success_url: "#{ENV['APP_URL'] || 'http://127.0.0.1:5000'}/billing?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "#{ENV['APP_URL'] || 'http://127.0.0.1:5000'}/upgrade",
        subscription_data: sub_data
      )
      redirect_to session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      Rails.logger.error("Signup plan choice checkout: #{e.message}")
      redirect_to upgrade_pricing_path, alert: t("controllers.pricing.payment_error")
    end
  end

  private

  def load_pending_plan
    pid = session[:post_signup_paid_plan_id]
    @pending_plan = pid.present? ? PricingPlan.find_by(id: pid) : nil
  end
end
