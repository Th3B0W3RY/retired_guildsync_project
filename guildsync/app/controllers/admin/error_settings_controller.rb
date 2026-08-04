# frozen_string_literal: true

module Admin
  class ErrorSettingsController < BaseController
    ERROR_SETTINGS_MAIN_FRAME = "admin_error_settings_main"

    def show
      load_assigns
      return render("error_settings_frame", layout: false) if request.headers["Turbo-Frame"] == ERROR_SETTINGS_MAIN_FRAME
    end

    def update
      cadence = Integer(params[:error_batch_cadence_hours], exception: false)
      if cadence.nil? || cadence < SiteSetting::ERROR_BATCH_CADENCE_MIN || cadence > SiteSetting::ERROR_BATCH_CADENCE_MAX
        msg = t("admin.error_settings.flash.invalid_cadence",
                min: SiteSetting::ERROR_BATCH_CADENCE_MIN,
                max: SiteSetting::ERROR_BATCH_CADENCE_MAX)
        return respond_with_message(msg, :alert)
      end

      immediate_sevs = Array(params[:error_immediate_severities])
                         .map(&:to_s)
                         .select { |s| ErrorLog::SEVERITIES.include?(s) }

      SiteSetting.set("error_batch_cadence_hours", cadence.to_s)
      SiteSetting.set("error_immediate_severities", immediate_sevs.to_json)
      log_admin_action(action: "update_error_notification_settings",
                       changes_data: { cadence_hours: cadence, immediate_severities: immediate_sevs })

      respond_with_message(t("admin.error_settings.flash.updated"), :notice)
    end

    private

    def load_assigns
      @cadence_hours        = SiteSetting.error_batch_cadence_hours
      @immediate_severities = SiteSetting.error_immediate_severities
      @all_severities       = ErrorLog::SEVERITIES
      @recent_reports       = ErrorBatchReport.recent.limit(5)
    end

    def respond_with_message(msg, variant)
      load_assigns
      @flash_message = msg
      @flash_variant = variant
      respond_to do |format|
        format.html do
          if variant == :notice
            redirect_to admin_error_notification_settings_path, notice: msg
          else
            redirect_to admin_error_notification_settings_path, alert: msg
          end
        end
        format.turbo_stream { render :update }
      end
    end
  end
end
