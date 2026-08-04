# frozen_string_literal: true

module Admin
  class SubscriptionsController < BaseController
    # Turbo Frame ids for paying / trials list refresh (search submit targets these).
    PAYING_RESULTS_FRAME = "admin_subscriptions_paying_main"
    TRIAL_RESULTS_FRAME = "admin_subscriptions_trial_main"

    def paying_users
      @query = sanitize_search_input(params[:q])

      @users = Admin::SubscriptionDirectory.paying_users_relation.order(:email)

      @users = @users.where("users.email ILIKE :q OR users.username ILIKE :q", q: ilike_query(@query)) if @query.present?

      return render("paying_users_frame", layout: false) if request.headers["Turbo-Frame"] == PAYING_RESULTS_FRAME
    end

    def trial_users
      @query = sanitize_search_input(params[:q])

      @users = Admin::SubscriptionDirectory.trials_and_free_users_relation.order(:email)

      @users = @users.where("users.email ILIKE :q OR users.username ILIKE :q", q: ilike_query(@query)) if @query.present?

      return render("trial_users_frame", layout: false) if request.headers["Turbo-Frame"] == TRIAL_RESULTS_FRAME
    end

    def search_paying
      query = sanitize_search_input(params[:q])
      
      if query.blank? || query.length < 1
        render json: { users: [] }
        return
      end
      
      base_query = Admin::SubscriptionDirectory.paying_users_relation
      
      users = base_query.where("users.email ILIKE :q OR users.username ILIKE :q", q: ilike_query(query))
                       .order(:email)
                       .limit(10)
      
      render json: { users: users.map { |u| subscription_search_json_row(u, include_trial_ends: false) } }
    end

    def search_trials
      query = sanitize_search_input(params[:q])
      
      if query.blank? || query.length < 1
        render json: { users: [] }
        return
      end
      
      base_query = Admin::SubscriptionDirectory.trials_and_free_users_relation
      
      users = base_query.where("users.email ILIKE :q OR users.username ILIKE :q", q: ilike_query(query))
                       .order(:email)
                       .limit(10)
      
      render json: { users: users.map { |u| subscription_search_json_row(u, include_trial_ends: true) } }
    end

    private

    def subscription_search_json_row(user, include_trial_ends:)
      sub = user.current_subscription
      row = {
        id: user.id,
        email: user.email,
        username: user.username,
        plan: subscription_json_plan(sub),
        status: subscription_json_status(sub)
      }
      row[:trial_ends_at] = sub.trial_ends_at.iso8601 if include_trial_ends && sub&.trial_ends_at
      row
    end

    def subscription_json_plan(subscription)
      return I18n.t("admin.subscriptions.json.no_plan") if subscription.nil? || subscription.pricing_plan.nil?

      subscription.pricing_plan.name
    end

    def subscription_json_status(subscription)
      return I18n.t("admin.subscriptions.json.status_none") if subscription.nil?

      I18n.t("admin.users.show.subscription_status.#{subscription.status}")
    end

    def ilike_query(input)
      "%#{ActiveRecord::Base.sanitize_sql_like(input)}%"
    end
  end
end
