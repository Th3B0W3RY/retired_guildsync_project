# frozen_string_literal: true

require "csv"

module Admin
  class OcrRequestsController < BaseController
    OCR_REQUESTS_INDEX_MAIN_FRAME = "admin_ocr_requests_index_main"
    OCR_REQUESTS_SHOW_MAIN_FRAME = "admin_ocr_requests_show_main"

    before_action :set_user, only: [ :show, :adjust_usage, :toggle_lock, :toggle_unlock, :reset_period, :update_notes ]

    def index
      load_ocr_index_assigns
      return render("ocr_requests_index_frame", layout: false) if request.headers["Turbo-Frame"] == OCR_REQUESTS_INDEX_MAIN_FRAME
    end

    def show
      load_ocr_show_assigns
      return render("ocr_requests_show_frame", layout: false) if request.headers["Turbo-Frame"] == OCR_REQUESTS_SHOW_MAIN_FRAME
    end

    def adjust_usage
      delta = params[:delta].to_i
      reason = params[:reason].to_s.strip
      if reason.blank?
        respond_ocr_user_alert(I18n.t("admin.ocr_requests.flash.reason_required"))
        return
      end
      if delta == 0
        respond_ocr_user_alert(I18n.t("admin.ocr_requests.flash.delta_nonzero"))
        return
      end
      before_period = @user.ocr_requests_used_this_period.to_i
      @user.with_lock do
        new_period = [ before_period + delta, 0 ].max
        @user.update_columns(
          ocr_requests_used_this_period: new_period,
          ocr_requests_used: [ (@user.ocr_requests_used.to_i + delta), 0 ].max
        )
        @user.ocr_usage_changes.create!(
          delta: delta,
          reason: reason,
          admin_email: current_admin_email,
          before_used_period: before_period,
          after_used_period: new_period,
          from_admin_panel: true,
          action_type: delta > 0 ? "increase" : "decrease"
        )
      end
      log_admin_action(action: "ocr_usage_adjust", record: @user, changes_data: { delta: delta, reason: reason })
      respond_ocr_user_notice(I18n.t("admin.ocr_requests.flash.usage_updated"))
    end

    def toggle_lock
      new_value = !@user.ocr_hard_locked
      @user.update_columns(ocr_hard_locked: new_value)
      @user.ocr_usage_changes.create!(
        delta: 0,
        reason: "Admin #{new_value ? 'locked' : 'unlocked'} OCR access",
        admin_email: current_admin_email,
        from_admin_panel: true,
        action_type: new_value ? "lock" : "unlock"
      )
      log_admin_action(action: "ocr_toggle_lock", record: @user, changes_data: { locked: new_value })
      notice = new_value ? I18n.t("admin.ocr_requests.flash.user_locked") : I18n.t("admin.ocr_requests.flash.user_unlocked")
      respond_ocr_user_notice(notice)
    end

    def toggle_unlock
      new_value = !@user.ocr_unlocked
      @user.update_columns(ocr_unlocked: new_value)
      @user.ocr_usage_changes.create!(
        delta: 0,
        reason: "Admin #{new_value ? 'granted' : 'revoked'} OCR unlock override",
        admin_email: current_admin_email,
        from_admin_panel: true,
        action_type: new_value ? "unlock_override" : "revoke_unlock"
      )
      log_admin_action(action: "ocr_toggle_unlock", record: @user, changes_data: { unlocked: new_value })
      notice = new_value ? I18n.t("admin.ocr_requests.flash.unlock_granted") : I18n.t("admin.ocr_requests.flash.unlock_revoked")
      respond_ocr_user_notice(notice)
    end

    def reset_period
      before_period = @user.ocr_requests_used_this_period.to_i
      @user.update_columns(
        ocr_requests_used_this_period: 0,
        ocr_last_reset_at: Time.current
      )
      @user.ocr_usage_changes.create!(
        delta: -before_period,
        reason: "Admin reset monthly counter",
        admin_email: current_admin_email,
        before_used_period: before_period,
        after_used_period: 0,
        from_admin_panel: true,
        action_type: "reset_period"
      )
      log_admin_action(action: "ocr_reset_period", record: @user, changes_data: { before: before_period })
      respond_ocr_user_notice(I18n.t("admin.ocr_requests.flash.monthly_reset"))
    end

    def update_notes
      @user.update_columns(ocr_notes: params[:ocr_notes].to_s)
      log_admin_action(action: "ocr_update_notes", record: @user)
      respond_ocr_user_notice(I18n.t("admin.ocr_requests.flash.notes_updated"))
    end

    def export
      users = User.order(ocr_requests_used_this_period: :desc)
      csv = CSV.generate(headers: true) do |row|
        row << [
          I18n.t("admin.ocr_requests.export.email"),
          I18n.t("admin.ocr_requests.export.username"),
          I18n.t("admin.ocr_requests.export.plan"),
          I18n.t("admin.ocr_requests.export.used_period"),
          I18n.t("admin.ocr_requests.export.limit"),
          I18n.t("admin.ocr_requests.export.locked"),
          I18n.t("admin.ocr_requests.export.unlocked"),
          I18n.t("admin.ocr_requests.export.last_reset")
        ]
        users.each do |u|
          row << [
            u.email,
            u.username,
            u.ocr_plan,
            u.respond_to?(:ocr_requests_used_this_period) ? u.ocr_requests_used_this_period : 0,
            u.ocr_monthly_limit,
            u.respond_to?(:ocr_hard_locked) && u.ocr_hard_locked,
            u.respond_to?(:ocr_unlocked) && u.ocr_unlocked,
            u.respond_to?(:ocr_last_reset_at) && u.ocr_last_reset_at ? u.ocr_last_reset_at.iso8601 : ""
          ]
        end
      end
      send_data csv, filename: "ocr_usage_#{Time.current.strftime('%Y%m%d')}.csv", type: "text/csv"
    end

    def bulk_action
      action = params[:bulk_action]
      user_ids = Array(params[:user_ids]).map(&:to_i).reject(&:zero?)
      if user_ids.empty?
        respond_ocr_index_bulk(:alert, I18n.t("admin.ocr_requests.flash.select_at_least_one"))
        return
      end
      users = User.where(id: user_ids)
      case action
      when "lock"
        users.update_all(ocr_hard_locked: true)
        log_admin_action(action: "ocr_bulk_lock", changes_data: { user_ids: user_ids, count: users.count })
        respond_ocr_index_bulk(:notice, I18n.t("admin.ocr_requests.flash.bulk_locked", count: users.count))
      when "unlock"
        users.update_all(ocr_hard_locked: false, ocr_unlocked: true)
        log_admin_action(action: "ocr_bulk_unlock", changes_data: { user_ids: user_ids, count: users.count })
        respond_ocr_index_bulk(:notice, I18n.t("admin.ocr_requests.flash.bulk_unlocked", count: users.count))
      when "reset"
        users.update_all(ocr_requests_used_this_period: 0, ocr_last_reset_at: Time.current)
        log_admin_action(action: "ocr_bulk_reset", changes_data: { user_ids: user_ids, count: users.count })
        respond_ocr_index_bulk(:notice, I18n.t("admin.ocr_requests.flash.bulk_reset", count: users.count))
      else
        respond_ocr_index_bulk(:alert, I18n.t("admin.ocr_requests.flash.unknown_bulk_action"))
      end
    end

    private

    def load_ocr_index_assigns
      @total_ocr_all_time = user_sum(:ocr_requests_used)
      @requests_this_month = user_sum(:ocr_requests_used_this_period)
      @users_near_limit = users_near_limit_count
      @users_at_hard_stop = users_at_hard_stop_count
      @abusive_ips_count = abusive_ips_count
      @suspicious_ips = suspicious_ips_list
      @locked_count = User.column_names.include?("ocr_hard_locked") ? User.where(ocr_hard_locked: true).count : 0
      @unlocked_count = User.column_names.include?("ocr_unlocked") ? User.where(ocr_unlocked: true).count : 0
      @trial_remaining = trial_users_count
      @query = sanitize_search_input(params[:q])
      @users = ocr_users_scope
      @user_ids_at_hard_stop = User.respond_to?(:at_ocr_hard_stop) ? User.at_ocr_hard_stop.pluck(:id).to_set : Set.new
    end

    def respond_ocr_index_bulk(variant, message)
      load_ocr_index_assigns
      @admin_ocr_index_flash_message = message
      @admin_ocr_index_flash_variant = variant
      respond_to do |format|
        format.html do
          path = admin_ocr_requests_path(q: params[:q].presence)
          if variant == :notice
            redirect_to path, notice: message
          else
            redirect_to path, alert: message
          end
        end
        format.turbo_stream { render :ocr_requests_index_refresh }
      end
    end

    def load_ocr_show_assigns
      @usage_changes = @user.ocr_usage_changes.recent.limit(50)
      if @user.respond_to?(:ocr_requests)
        @recent_ocr_requests = @user.ocr_requests.includes(:initiated_by).order(created_at: :desc).limit(20)
      end
      @recent_denials = @user.ocr_denials.order(created_at: :desc).limit(20) if @user.respond_to?(:ocr_denials)
    end

    def reload_ocr_user_show_assigns
      @user.reload
      @usage_changes = @user.ocr_usage_changes.recent.limit(50)
    end

    def respond_ocr_user_notice(notice)
      @admin_ocr_notice = notice
      reload_ocr_user_show_assigns
      respond_to do |format|
        format.html { redirect_to admin_ocr_request_user_path(@user), notice: notice }
        format.turbo_stream { render :ocr_user_refresh }
      end
    end

    def respond_ocr_user_alert(alert)
      @admin_ocr_alert = alert
      respond_to do |format|
        format.html { redirect_to admin_ocr_request_user_path(@user), alert: alert }
        format.turbo_stream { render :ocr_user_flash_alert }
      end
    end

    def set_user
      @user = User.find(params[:user_id])
    end

    def user_sum(col)
      return 0 unless User.column_names.include?(col.to_s)
      with_savepoint("user_sum_#{col}") { User.sum(col) }
    rescue ActiveRecord::StatementInvalid
      0
    end

    def users_near_limit_count
      return 0 unless User.respond_to?(:near_ocr_limit)
      with_savepoint("users_near_limit") { User.near_ocr_limit(0.8).count }
    rescue ActiveRecord::StatementInvalid
      0
    end

    def users_at_hard_stop_count
      return 0 unless User.respond_to?(:at_ocr_hard_stop)
      with_savepoint("users_at_hard_stop") { User.at_ocr_hard_stop.count }
    rescue ActiveRecord::StatementInvalid
      0
    end

    def abusive_ips_count
      return 0 unless defined?(AbuseFlag)
      AbuseFlag.where(target_type: "IP").recent.count
    rescue ActiveRecord::StatementInvalid
      0
    end

    def suspicious_ips_list
      return [] unless defined?(OcrRequest) && OcrRequest.column_names.include?("ip_address")
      OcrRequest.where.not(ip_address: [ nil, "" ])
                .where("created_at > ?", 24.hours.ago)
                .group(:ip_address)
                .count
                .select { |_ip, count| count >= 100 }
                .sort_by { |_ip, count| -count }
                .first(20)
                .map { |ip, count| { ip: ip, count: count } }
    rescue ActiveRecord::StatementInvalid
      []
    end

    def trial_users_count
      return 0 unless User.column_names.include?("ocr_billing_plan")
      with_savepoint("trial_users") do
        User.where(ocr_billing_plan: "trial").where("trial_expired_at IS NULL OR trial_expired_at > ?", Time.current).count
      end
    rescue ActiveRecord::StatementInvalid
      0
    end

    def with_savepoint(_name)
      return yield unless ActiveRecord::Base.connection.transaction_open?

      ActiveRecord::Base.transaction(requires_new: true) { yield }
    end

    def ocr_users_scope
      page = [ (params[:page].to_i || 1), 1 ].max
      per = 25
      base = User.order(created_at: :desc)
      base = base.where("email ILIKE ? OR username ILIKE ?", "%#{@query}%", "%#{@query}%") if @query.present?
      base = base.order(ocr_requests_used_this_period: :desc) if User.column_names.include?("ocr_requests_used_this_period")
      base.offset((page - 1) * per).limit(per)
    end
  end
end
