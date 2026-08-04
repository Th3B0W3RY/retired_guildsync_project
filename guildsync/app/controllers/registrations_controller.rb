class RegistrationsController < Devise::RegistrationsController
  include MfaVerification
  include SignupCaptchaVerifiable

  layout "application"

  before_action :redirect_if_authenticated, only: [ :new, :create ]
  before_action :configure_sign_up_params, only: [ :create ]
  before_action :configure_account_update_params, only: [ :update ]

  def new
    redirect_to create_account_path
    return

    # Store selected plan_id in session if provided from pricing page
    if params[:plan_id].present?
      # Sanitize plan_id before storing
      plan_id = sanitize_plan_id(params[:plan_id])
      session[:selected_plan_id] = plan_id if plan_id.present?
    end
    super
  end

  def create
    redirect_to create_account_path, alert: I18n.t("account_creation.use_new_flow")
    return

    unless signup_turnstile_result == :ok
      build_resource(sign_up_params)
      resource.errors.add(:base, I18n.t("registrations.errors.captcha_invalid"))
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
      return
    end

    # Security: ONLY accept params[:plan_id] from URL (pricing page)
    # NEVER trust params[:selected_plan_id] from form
    selected_plan_id = params[:plan_id] || session[:selected_plan_id]

    # Early guard: check if PricingPlan table exists before any usage
    unless defined?(PricingPlan) && PricingPlan.table_exists?
      selected_plan_id = nil
    end

    # Sanitize plan_id using regex
    selected_plan_id = sanitize_plan_id(selected_plan_id) if selected_plan_id.present?

    # Validate plan exists and is NOT Free (Free plan not selectable at signup)
    if selected_plan_id.present?
      plan = PricingPlan.find_by(id: selected_plan_id)
      if plan.nil? || plan.name == "Free"
        selected_plan_id = nil # Invalid plan or Free plan, clear it
        session.delete(:selected_plan_id)
      end
    end

    build_resource(sign_up_params)
    resource.signup_ip = request.remote_ip if resource.respond_to?(:signup_ip=)

    resource.save
    yield resource if block_given?

    if resource.persisted?
      # Basic-only trial at signup; Upgraded/Elite → MFA first, then plan-choice / checkout
      if selected_plan_id.present?
        begin
          plan = PricingPlan.find_by(id: selected_plan_id)
          if plan && plan.name != "Free"
            if plan.name.to_s.strip.casecmp?("basic")
              free_plan = PricingPlan.find_by(name: "Free")
              if free_plan
                resource.subscriptions.where(pricing_plan: free_plan).destroy_all
              end
              resource.create_trial_at_signup!(plan)
              Rails.logger.info "Created 14-day Basic trial for user #{resource.id}"
            else
              session[:post_signup_paid_plan_id] = plan.id
              resource.ensure_free_plan_subscription unless resource.subscriptions.current.exists?
            end
          end
        rescue => e
          Rails.logger.error "Failed to create trial at signup: #{e.message}"
          resource.ensure_free_plan_subscription unless resource.subscriptions.current.exists?
        end
      else
        # No trial selected - ensure free plan exists (callback should have created it, but double-check)
        resource.ensure_free_plan_subscription unless resource.subscriptions.current.exists?
      end

      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        # Backup for session loss across redirect (same as SessionsController)
        session[:user_id] = resource.id
        session[:just_logged_in] = true
        session.save if session.respond_to?(:save)
        session.commit if session.respond_to?(:commit)
        warden.set_user(resource, scope: :user) unless warden.user(scope: :user) == resource
        # Force redirect to MFA setup after successful registration
        redirect_to after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    else
      # Clear session plan if signup fails
      session.delete(:selected_plan_id)
      session.delete(:plan_id_frozen)
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  protected

  def after_inactive_sign_up_path_for(_resource)
    login_path
  end

  def after_sign_up_path_for(resource)
    # Redirect to MFA setup after registration (mandatory)
    mfa_setup_path
  end

  private

  def configure_sign_up_params
    # Security: Do NOT permit selected_plan_id from form params
    # Only accept it from session or URL params (plan_id)
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :username ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :username ])
  end

  def redirect_if_authenticated
    # Only redirect if user is FULLY authenticated (signed in AND MFA verified)
    # This allows users with stale sessions to sign up with a different email
    if user_signed_in? && current_user.present? && mfa_verified_for_session?
      redirect_to dashboard_path, alert: "You are already signed in." if request.get? && !request.xhr?
    elsif user_signed_in? && current_user.present?
      # User is signed in but not fully authenticated - clear stale session and allow signup
      Rails.logger.info("Clearing stale session in RegistrationsController for user #{current_user.id}")
      reset_session
      flash.clear
    end
  end

  def sanitize_plan_id(value)
    return nil unless value.present?

    # Only allow digits, prevent dangerous inputs
    if value.to_s =~ /\A\d+\z/
      plan_id = value.to_i
      # Additional safety check for reasonable integer range
      if plan_id > 0 && plan_id < 2_147_483_647
        plan_id
      else
        nil # Out of range
      end
    else
      nil # Invalid format
    end
  end
end
