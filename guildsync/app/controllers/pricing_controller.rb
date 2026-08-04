class PricingController < ApplicationController
  layout "application"

  skip_before_action :authenticate_user!, only: [ :public_pricing, :select_plan ]
  skip_before_action :require_mfa_if_enabled, only: [ :public_pricing, :select_plan ]

  before_action :authenticate_user!, only: [ :upgrade ]
  before_action :require_mfa_if_enabled, only: [ :upgrade ]

  # Logged-out marketing page
  def public_pricing
    redirect_to upgrade_pricing_path if user_signed_in?
    @plans = PricingPlan.active.order(:display_order)
  end

  # Logged-in upgrade page
  def upgrade
    @plans = PricingPlan.active.order(:display_order)
    @current_plan = current_user.current_plan
    @subscription = current_user.current_subscription
  end

  # Handle plan selection
  def select_plan
    plan = PricingPlan.find_by(id: params[:id])

    unless plan
      flash[:alert] = t('controllers.pricing.plan_not_found')
      redirect_to user_signed_in? ? upgrade_pricing_path : pricing_path
      return
    end

    if user_signed_in? && current_user.present?
      begin
        # Check if user is currently in trial
        if current_user.trial_active?
          if plan.name == "Free"
            current_user.downgrade_to_free_during_trial!
            flash[:notice] = t('controllers.pricing.trial_switched_free')
          elsif plan.name.to_s.strip.casecmp?("basic")
            current_user.switch_plan_during_trial!(plan)
            flash[:notice] = t('controllers.pricing.plan_switched_trial', plan: plan.name)
          else
            redirect_to_stripe_checkout!(plan); return
          end
        elsif current_user.current_subscription&.pricing_plan&.name == "Free"
          # User is on Free plan
          if plan.name == "Free"
            flash[:notice] = t('controllers.pricing.already_free')
          elsif current_user.can_start_trial? && plan.name.to_s.strip.casecmp?("basic")
            current_user.start_trial_from_free!(plan)
            flash[:notice] = t('controllers.pricing.trial_started', plan: plan.name)
          else
            redirect_to_stripe_checkout!(plan); return
          end
        elsif current_user.subscribed?
          # Post-trial: require Stripe payment for paid plans
          if plan.name == "Free"
            current_user.activate_free_plan!
            flash[:notice] = t('controllers.pricing.switched_to_free')
          else
            redirect_to_stripe_checkout!(plan); return
          end
        else
          # No active subscription - ensure free plan exists
          current_user.ensure_free_plan_subscription
          if plan.name == "Free"
            flash[:notice] = t('controllers.pricing.switched_to_free')
          elsif current_user.can_start_trial? && plan.name.to_s.strip.casecmp?("basic")
            current_user.start_trial_from_free!(plan)
            flash[:notice] = t('controllers.pricing.trial_started', plan: plan.name)
          else
            redirect_to_stripe_checkout!(plan); return
          end
        end
        redirect_to upgrade_pricing_path
      rescue => e
        Rails.logger.error "Failed to update plan: #{e.message}"
        flash[:alert] = t('controllers.pricing.update_failed')
        redirect_to upgrade_pricing_path
      end
    else
      # Not logged in - store plan selection for signup (Free plan not selectable)
      if plan.name == "Free"
        flash[:alert] = t('controllers.pricing.free_not_at_signup')
        redirect_to pricing_path
        return
      end

      session[:selected_plan_id] = plan.id
      session[:plan_id_frozen] = true
      redirect_to sign_up_path(plan_id: plan.id)
    end
  end

  private

  def redirect_to_stripe_checkout!(plan)
    unless plan.effective_stripe_price_id.present?
      flash[:alert] = t("controllers.pricing.not_available")
      redirect_to upgrade_pricing_path
      return
    end

    customer_id = current_user.stripe_customer_id
    unless customer_id
      customer = Stripe::Customer.create(email: current_user.email)
      current_user.update!(stripe_customer_id: customer.id)
      customer_id = customer.id
    end

    sub_data = {
      metadata: {
        user_id: current_user.id.to_s,
        plan_id: plan.id.to_s
      }
    }
    td = Billing::TrialPolicy.stripe_trial_period_days(plan)
    sub_data[:trial_period_days] = td if td.present?

    session = Stripe::Checkout::Session.create(
      customer: customer_id,
      mode: "subscription",
      line_items: [{ price: plan.effective_stripe_price_id, quantity: 1 }],
      success_url: "#{ENV['APP_URL'] || 'http://127.0.0.1:5000'}/billing?success=true",
      cancel_url: "#{ENV['APP_URL'] || 'http://127.0.0.1:5000'}/billing?canceled=true",
      subscription_data: sub_data
    )
    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error("Stripe error: #{e.message}")
    flash[:alert] = t("controllers.pricing.payment_error")
    redirect_to upgrade_pricing_path
  end
end
