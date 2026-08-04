# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    USERS_INDEX_RESULTS_FRAME = "admin_users_index_results"
    USERS_SHOW_MAIN_FRAME = "admin_users_show_main"

    def index
      load_users_index
      if request.headers["Turbo-Frame"] == USERS_INDEX_RESULTS_FRAME
        render "users_index_results_frame", layout: false
      end
    end

    def search
      query = sanitize_search_input(params[:q])
      
      if query.blank? || query.length < 1
        render json: { users: [] }
        return
      end
      
      users = User.where(
        "email ILIKE ? OR username ILIKE ?",
        "%#{query}%",
        "%#{query}%"
      ).order(:email).limit(10)
      
      render json: {
        users: users.map { |u| 
          {
            id: u.id,
            email: u.email,
            username: u.username,
            plan: u.current_subscription&.pricing_plan&.name || "No Plan",
            status: u.current_subscription&.status || "none"
          }
        }
      }
    end

    def show
      @user = User.find(params[:id])
      @current_subscription = @user.current_subscription
      @pricing_plans = PricingPlan.active.ordered
      @account_deletion_eligible_reactivate = AccountClosure::AdminRestore.eligible?(@user)
      if request.headers["Turbo-Frame"] == USERS_SHOW_MAIN_FRAME
        render "users_show_frame", layout: false
      end
    end

    def reactivate_account
      @user = User.find(params[:id])
      result = AccountClosure::AdminRestore.new(@user).call

      unless result.ok?
        alert_key = case result.error_key
        when :outside_retention
                      "admin.users.reactivate.outside_retention"
        when :hard_purged
                      "admin.users.reactivate.hard_purged"
        else
                      "admin.users.reactivate.not_applicable"
        end
        redirect_to admin_user_path(@user), alert: I18n.t(alert_key, months: (SoftDeletable::RETENTION_PERIOD / 1.month).to_i)
        return
      end

      @user.reload
      log_admin_action(
        action: "reactivate_account_after_deletion_request",
        record: @user,
        changes_data: { reactivated_at: Time.current.iso8601 }
      )
      redirect_to admin_user_path(@user), notice: I18n.t("admin.users.reactivate.success")
    end

    def update_trial
      @user = User.find(params[:id])
      action = params[:action_type]

      case action
      when "extend_1_week"
        current_end = @user.current_subscription&.trial_ends_at || Time.current
        extend_trial(@user, [ current_end, Time.current ].max + 1.week)
      when "extend_2_weeks"
        current_end = @user.current_subscription&.trial_ends_at || Time.current
        extend_trial(@user, [ current_end, Time.current ].max + 2.weeks)
      when "extend_1_month"
        current_end = @user.current_subscription&.trial_ends_at || Time.current
        extend_trial(@user, [ current_end, Time.current ].max + 1.month)
      when "extend_custom"
        if params[:custom_date].blank?
          respond_trial_alert(I18n.t("admin.users.trial_flash.select_date"))
          return
        end
        begin
          custom_date = if params[:custom_date].is_a?(String)
            Date.parse(params[:custom_date])
          else
            params[:custom_date].to_date
          end
          new_trial_end = custom_date.end_of_day
          extend_trial(@user, new_trial_end)
        rescue ArgumentError, Date::Error => e
          Rails.logger.error "Date parsing error: #{e.message} for date: #{params[:custom_date].inspect}"
          respond_trial_alert(I18n.t("admin.users.trial_flash.invalid_date"))
          return
        end
      when "remove"
        remove_trial(@user)
      when "add"
        add_trial(@user, params[:plan_id])
      else
        respond_trial_alert(I18n.t("admin.users.trial_flash.invalid_action"))
        return
      end

      log_admin_action(action: "update_trial", record: @user, changes_data: { action_type: action })
      reload_subscription_trial_context
      respond_trial_notice(I18n.t("admin.users.trial_flash.updated"))
    rescue => e
      Rails.logger.error "Admin trial update error: #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}"
      respond_trial_alert(I18n.t("admin.users.trial_flash.update_failed", message: e.message))
    end

    private

    def load_users_index
      @query = sanitize_search_input(params[:q])

      scope = if @query.present?
        User.where(
          "email ILIKE ? OR username ILIKE ?",
          "%#{@query}%",
          "%#{@query}%"
        )
      else
        User.all
      end
      @users = scope.includes(current_subscription: :pricing_plan).order(created_at: :desc).limit(50)
    end

    def reload_subscription_trial_context
      @user.reload
      @current_subscription = @user.current_subscription
      @pricing_plans = PricingPlan.active.ordered
    end

    def respond_trial_notice(message)
      @admin_trial_message = message
      respond_to do |format|
        format.html { redirect_to admin_user_path(@user), notice: message }
        format.turbo_stream { render :subscription_trial_refresh }
      end
    end

    def respond_trial_alert(message)
      @admin_trial_message = message
      respond_to do |format|
        format.html { redirect_to admin_user_path(@user), alert: message }
        format.turbo_stream { render :subscription_trial_alert_flash }
      end
    end

    # CRITICAL: Trial management must ONLY touch Subscription records. Never update the User
    # model here (no user.update, user.save, or user.assign_attributes). Updating User
    # can trigger callbacks or mass-assignment that corrupts authentication data
    # (encrypted_password, uid, provider, otp_secret, mfa_*, etc.) and blocks sign-in.

    def extend_trial(user, new_end_date)
      subscription = user.current_subscription || user.subscriptions.current.first

      if subscription
        # Use update_columns to skip callbacks and validations; only touch subscription fields.
        subscription.update_columns(
          status: Subscription.statuses[:trialing],
          trial_ends_at: new_end_date,
          updated_at: Time.current
        )
        user.association(:current_subscription).reload
        subscription.reload
      else
        # Create new trial subscription (no User record is saved).
        free_plan = PricingPlan.find_by(name: "Free") || PricingPlan.active.first
        user.subscriptions.create!(
          pricing_plan: free_plan,
          status: :trialing,
          started_at: Time.current,
          trial_ends_at: new_end_date
        )
        user.association(:current_subscription).reload
      end
    end

    def remove_trial(user)
      subscription = user.current_subscription || user.subscriptions.current.first

      if subscription && subscription.in_trial?
        subscription.update_columns(
          status: Subscription.statuses[:active],
          trial_ends_at: nil,
          updated_at: Time.current
        )
        user.association(:current_subscription).reload
        subscription.reload
      end
    end

    def add_trial(user, plan_id)
      plan = PricingPlan.find(plan_id)

      user.subscriptions.where(status: [ :active, :trialing ]).update_all(
        status: Subscription.statuses[:canceled],
        canceled_at: Time.current
      )

      user.subscriptions.create!(
        pricing_plan: plan,
        status: :trialing,
        started_at: Time.current,
        trial_ends_at: User::STANDARD_TRIAL_PERIOD_DAYS.days.from_now
      )
      user.association(:current_subscription).reload
    end
  end
end
