class BillingController < ApplicationController
  before_action :authenticate_user!
  before_action :detect_json_format, only: [:create_portal_session, :checkout, :change_plan, :preview_plan_change, :cancel_subscription, :resume_subscription]
  before_action :require_stripe_subscription!, only: [:change_plan, :preview_plan_change, :cancel_subscription, :resume_subscription]

  def show
    # Handle Stripe Checkout success callback
    if params[:session_id].present?
      handle_checkout_success(params[:session_id])
      return
    end

    # Ensure user is authenticated - if not, redirect to login
    unless user_signed_in? && current_user.present?
      redirect_to login_path, alert: t("controllers.billing.sign_in_required")
      return
    end

    @subscription = current_user.current_subscription
    @pricing_plan = @subscription&.pricing_plan
    @plans = PricingPlan.active.where.not(name: "Free").order(:display_order)

    # Calculate trial days remaining
    @trial_days_remaining = nil
    if @subscription&.in_trial? && @subscription.trial_ends_at.present?
      days = ((@subscription.trial_ends_at - Time.current) / 1.day).ceil
      @trial_days_remaining = [ days, 0 ].max
    end

    load_stripe_billing_extras
  end

  def change_plan
    plan = PricingPlan.active.find_by(id: params[:plan_id])
    unless plan
      respond_to_change(format_message: t("controllers.billing.plan_not_found"), success: false)
      return
    end

    result = SubscriptionPlanChangeService.call(
      user: current_user,
      target_plan: plan,
      interval: params[:interval]
    )

    if result.ok
      respond_to_change(
        format_message: t("controllers.billing.plan_changed"),
        success: true
      )
    else
      respond_to_change(format_message: result.error, success: false)
    end
  end

  def preview_plan_change
    plan = PricingPlan.active.find_by(id: params[:plan_id])
    unless plan
      respond_to do |format|
        format.json do
          render json: { error: t("controllers.billing.plan_not_found") }, status: :not_found
        end
        format.html do
          redirect_to billing_path, alert: t("controllers.billing.plan_not_found")
        end
      end
      return
    end

    preview = SubscriptionPlanPreviewService.call(
      user: current_user,
      target_plan: plan,
      interval: params[:interval]
    )

    if preview
      amount = preview[:amount_due].to_f / 100
      render json: {
        amount_due: preview[:amount_due],
        currency: preview[:currency],
        formatted: helpers.number_to_currency(amount, unit: currency_unit_for(preview[:currency]))
      }
    else
      render json: { amount_due: nil, currency: nil, formatted: nil }
    end
  end

  def cancel_subscription
    result = SubscriptionCancellationService.call(user: current_user)

    if result.ok
      key = case result.mode
            when :refund_and_cancel then "controllers.billing.canceled_with_refund"
            when :period_end then "controllers.billing.canceled_at_period_end"
            else "controllers.billing.canceled"
            end
      respond_to_change(format_message: t(key), success: true)
    else
      respond_to_change(format_message: result.error, success: false)
    end
  end

  def resume_subscription
    result = SubscriptionCancellationService.resume!(user: current_user)

    if result.ok
      respond_to_change(format_message: t("controllers.billing.subscription_resumed"), success: true)
    else
      respond_to_change(format_message: result.error, success: false)
    end
  end

  def create_portal_session
    # Handle JSON requests (for API/testing) using respond_to
    # Rails automatically detects .json extension and sets format
    respond_to do |format|
      format.json do
        portal
        return
      end
      
      format.html do
        # HTML requests - redirect logic
        # Ensure session is saved before redirecting to external URL
        session.save if session.respond_to?(:save)
        
        @subscription = current_user.current_subscription
        
        # Allow plan_id parameter to override current subscription plan
        plan_id = params[:plan_id] || @subscription&.pricing_plan&.id
        plan = plan_id ? PricingPlan.find_by(id: plan_id) : @subscription&.pricing_plan

        # If no plan specified and no current subscription, redirect to pricing
        unless plan
          redirect_to upgrade_pricing_path, alert: t("controllers.billing.select_plan")
          return
        end

        # If user has Stripe customer ID, use Billing Portal to manage payment methods
        if @subscription&.stripe_customer_id.present?
          begin
            portal_session = Stripe::BillingPortal::Session.create(
              customer: @subscription.stripe_customer_id,
              return_url: billing_url
            )
            log_security_event(
              event: "billing.portal_session",
              status: "success",
              actor: current_user,
              metadata: { customer_id_present: true }
            )
            redirect_to portal_session.url, allow_other_host: true
          rescue Stripe::StripeError => e
            log_security_event(
              event: "billing.portal_session",
              status: "error",
              actor: current_user,
              metadata: { error_class: e.class.name }
            )
            Rails.logger.error("Stripe billing portal error: #{e.message}")
            redirect_to billing_path, alert: t("controllers.billing.portal_unavailable")
          rescue => e
            log_security_event(
              event: "billing.portal_session",
              status: "error",
              actor: current_user,
              metadata: { error_class: e.class.name }
            )
            Rails.logger.error("Billing portal error: #{e.message}")
            redirect_to billing_path, alert: t("controllers.billing.error_occurred")
          end
          return
        end

        # If plan has Stripe price ID, create Stripe Checkout session
        if plan.name != "Free" && plan.effective_stripe_price_id.present?
          begin
            # Create Stripe Checkout session for payment setup (uses DB or ENV price ID)
            checkout_session = Stripe::Checkout::Session.create(
              mode: "subscription",
              success_url: billing_url + "?session_id={CHECKOUT_SESSION_ID}",
              cancel_url: billing_url,
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
              subscription_data: billing_checkout_subscription_data(plan),
              payment_method_collection: "always"
            )

            log_security_event(
              event: "billing.checkout_session",
              status: "success",
              actor: current_user,
              metadata: { plan_id: plan.id, stripe_price_id: plan.effective_stripe_price_id }
            )
            redirect_to checkout_session.url, allow_other_host: true
          rescue Stripe::StripeError => e
            log_security_event(
              event: "billing.checkout_session",
              status: "error",
              actor: current_user,
              metadata: { plan_id: plan.id, error_class: e.class.name }
            )
            Rails.logger.error("Stripe checkout error: #{e.class.name}: #{e.message}")
            Rails.logger.error(e.backtrace.first(5).join("\n"))
            redirect_to billing_path, alert: t("controllers.billing.payment_session_failed", error: e.message)
          rescue => e
            log_security_event(
              event: "billing.checkout_session",
              status: "error",
              actor: current_user,
              metadata: { plan_id: plan.id, error_class: e.class.name }
            )
            Rails.logger.error("Checkout session error: #{e.message}")
            redirect_to billing_path, alert: t("controllers.billing.error_occurred")
          end
          return
        end

        # If plan doesn't have stripe_price_id, redirect to subscribe route which will handle it
        if plan.name != "Free"
          redirect_to subscribe_path(plan_id: plan.id)
          return
        end

        # Fallback: redirect to pricing page
        redirect_to upgrade_pricing_path, alert: t("controllers.billing.select_plan")
      end
    end
  end

  def checkout
    # Allow trial users to set up payment; block only non-trial users who already have Stripe subscription
    if current_user.stripe_subscription_id.present? && !current_user.trial_active?
      render json: { error: t("controllers.billing.checkout_active_subscription_use_portal") }, status: :bad_request
      return
    end

    price = params[:price_id] || params[:price]
    unless price
      render json: { error: t("controllers.billing.checkout_price_id_required") }, status: :bad_request
      return
    end

    begin
      # Ensure customer exists
      customer_id = current_user.stripe_customer_id
      unless customer_id
        customer = Stripe::Customer.create(email: current_user.email.presence || "user-#{current_user.id}@guildsync.placeholder")
        current_user.update!(stripe_customer_id: customer.id)
        customer_id = customer.id
      end

      plan = PricingPlan.find_by_effective_stripe_price(price)
      is_requests_addon = (price == ENV["STRIPE_REQUESTS_ADDON_PRICE_ID"])
      metadata = { user_id: current_user.id.to_s }
      metadata[:plan_id] = plan.id.to_s if plan
      subscription_data = { metadata: metadata }
      unless is_requests_addon
        td = plan ? Billing::TrialPolicy.stripe_trial_period_days(plan) : nil
        subscription_data[:trial_period_days] = td if td.present?
      end

      session = Stripe::Checkout::Session.create(
        customer: customer_id,
        mode: "subscription",
        line_items: [{ price: price, quantity: 1 }],
        success_url: "#{ENV['APP_URL'] || 'http://127.0.0.1:5000'}/billing?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "#{ENV['APP_URL'] || 'http://127.0.0.1:5000'}/billing?canceled=true",
        metadata: metadata,
        subscription_data: subscription_data
      )

      render json: { url: session.url }
    rescue Stripe::StripeError => e
      Rails.logger.error("Billing checkout Stripe error: #{e.class} - #{e.message}")
      render json: { error: t("controllers.billing.checkout_payment_setup_failed") }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("Billing checkout error: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      render json: { error: t("controllers.billing.checkout_failed") }, status: :internal_server_error
    end
  end

  private

  def billing_checkout_subscription_data(plan)
    sub = current_user.current_subscription
    td = Billing::TrialPolicy.stripe_trial_period_days(plan)
    td = nil if sub&.in_trial? && sub.pricing_plan_id == plan.id
    h = {
      metadata: {
        user_id: current_user.id.to_s,
        plan_id: plan.id.to_s
      }
    }
    h[:trial_period_days] = td if td.present?
    h
  end

  def require_stripe_subscription!
    sub = current_user.current_subscription
    unless sub&.stripe_subscription_id.present?
      respond_to do |format|
        format.json do
          render json: { error: t("controllers.billing.no_stripe_subscription") }, status: :unprocessable_content
        end
        format.html { redirect_to billing_path, alert: t("controllers.billing.no_stripe_subscription") }
      end
      return
    end
  end

  def respond_to_change(format_message:, success:)
    respond_to do |format|
      format.json do
        if success
          render json: { redirect_url: billing_url, message: format_message }
        else
          render json: { error: format_message }, status: :unprocessable_content
        end
      end
      format.html do
        if success
          redirect_to billing_path, notice: format_message
        else
          redirect_to billing_path, alert: format_message
        end
      end
    end
  end

  def currency_unit_for(currency)
    case currency.to_s.downcase
    when "usd" then "$"
    when "eur" then "€"
    when "gbp" then "£"
    else "#{currency.to_s.upcase} "
    end
  end

  def load_stripe_billing_extras
    @subscription ||= current_user.current_subscription
    @stripe_customer_balance_cents = nil
    @stripe_cancel_at_period_end = false
    @stripe_current_period_end = nil

    return unless @subscription&.stripe_customer_id.present?

    begin
      cust = Stripe::Customer.retrieve(@subscription.stripe_customer_id)
      @stripe_customer_balance_cents = cust.balance.to_i
    rescue Stripe::StripeError
      @stripe_customer_balance_cents = nil
    end

    return unless @subscription.stripe_subscription_id.present?

    begin
      ss = Stripe::Subscription.retrieve(@subscription.stripe_subscription_id)
      @stripe_cancel_at_period_end = ss.cancel_at_period_end
      @stripe_current_period_end = Time.zone.at(ss.current_period_end)
    rescue Stripe::StripeError
      @stripe_cancel_at_period_end = false
      @stripe_current_period_end = nil
    end
  end

  def detect_json_format
    # Rails automatically sets format from path extension (.json)
    # But we also check Accept header and format parameter
    # Check if Rails already set the format (most reliable)
    if request.format.json?
      return
    end
    
    # Check path for .json extension (fallback - Rails may not have parsed format yet)
    path = request.original_fullpath || request.fullpath || request.path_info || request.path || ""
    if path.to_s.ends_with?(".json") || path.to_s.include?(".json")
      request.format = :json
      return
    end
    
    # Check Accept header
    accept_header = request.headers["HTTP_ACCEPT"] || request.headers["Accept"] || ""
    if accept_header.include?("application/json")
      request.format = :json
      return
    end
    
    # Check format parameter
    if params[:format] == "json"
      request.format = :json
    end
  end

  def handle_checkout_success(session_id)
    begin
      session = Stripe::Checkout::Session.retrieve(session_id)

      # Validate session metadata
      unless session.metadata && session.metadata.user_id
        redirect_to billing_path, alert: t("controllers.billing.invalid_session")
        return
      end

      unless session.metadata.user_id.to_i == current_user.id
        redirect_to billing_path, alert: t("controllers.billing.session_mismatch")
        return
      end

      if session.payment_status == "paid" && session.subscription
        stripe_sub = Stripe::Subscription.retrieve(session.subscription)
        plan_id = session.metadata.plan_id

        if plan_id.present?
          plan = PricingPlan.find_by(id: plan_id)
          if plan
            subscription = current_user.subscriptions.find_or_initialize_by(
              stripe_subscription_id: stripe_sub.id
            )
            subscription.assign_attributes(
              pricing_plan: plan,
              stripe_customer_id: session.customer,
              stripe_subscription_id: stripe_sub.id,
              stripe_price_id: stripe_sub.items.data.first.price.id,
              status: :active,
              started_at: Time.at(stripe_sub.current_period_start),
              expires_at: nil,
              trial_ends_at: stripe_sub.trial_end ? Time.at(stripe_sub.trial_end) : nil
            )
            subscription.save!
            current_user.subscriptions
              .where.not(id: subscription.id)
              .where(status: [ :active, :trialing ])
              .update_all(status: :canceled, canceled_at: Time.current)
            log_security_event(
              event: "billing.checkout_success",
              status: "success",
              actor: current_user,
              metadata: { plan_id: plan.id, stripe_subscription_id: stripe_sub.id }
            )
          end
        end
        # If no plan_id (e.g. requests add-on), Stripe has the subscription; user can manage in portal
        redirect_to dashboard_path, notice: t("controllers.billing.checkout_success")
      else
        log_security_event(
          event: "billing.checkout_success",
          status: "failure",
          actor: current_user,
          metadata: { payment_status: session.payment_status.to_s }
        )
        redirect_to billing_path, alert: t("controllers.billing.payment_not_completed")
      end
    rescue Stripe::StripeError => e
      log_security_event(
        event: "billing.checkout_success",
        status: "error",
        actor: current_user,
        metadata: { error_class: e.class.name }
      )
      Rails.logger.error("Stripe error in billing: #{e.message}")
      redirect_to billing_path, alert: t("controllers.billing.payment_processing_error")
    rescue => e
      log_security_event(
        event: "billing.checkout_success",
        status: "error",
        actor: current_user,
        metadata: { error_class: e.class.name }
      )
      Rails.logger.error("Billing checkout success error: #{e.message}")
      redirect_to billing_path, alert: t("controllers.billing.contact_support")
    end
  end

  def portal
    customer_id = current_user.stripe_customer_id

    unless customer_id
      # Create customer if missing
      begin
        customer = Stripe::Customer.create(email: current_user.email)
        current_user.update!(stripe_customer_id: customer.id)
        customer_id = customer.id
      rescue Stripe::StripeError => e
        Rails.logger.error "Failed to create Stripe customer: #{e.message}"
        render json: { error: t("controllers.billing.portal_customer_init_failed") }, status: :internal_server_error
        return
      end
    end

    begin
      session = Stripe::BillingPortal::Session.create({
        customer: customer_id,
        return_url: "#{ENV['APP_URL'] || 'http://127.0.0.1:5000'}/billing"
      })

      render json: { url: session.url }
    rescue Stripe::StripeError => e
      Rails.logger.error "Failed to create billing portal session: #{e.message}"
      render json: { error: t("controllers.billing.portal_session_create_failed") }, status: :internal_server_error
    end
  end
end
