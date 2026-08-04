# frozen_string_literal: true

module Admin
  class FlashSettingsController < BaseController
    FLASH_SETTINGS_MAIN_FRAME = "admin_flash_settings_main"

    def show
      load_flash_settings_show
      return render("flash_settings_show_frame", layout: false) if request.headers["Turbo-Frame"] == FLASH_SETTINGS_MAIN_FRAME
    end

    def update
      @duration_ms = SiteSetting.flash_toast_duration_ms
      ms = Integer(params[:flash_toast_duration_ms], exception: false)
      if ms.nil?
        respond_flash_settings_update(t("admin.flash_settings.invalid_duration"), :alert)
        return
      end

      if ms < SiteSetting::FLASH_TOAST_DURATION_MIN_MS || ms > SiteSetting::FLASH_TOAST_DURATION_MAX_MS
        respond_flash_settings_update(
          t("admin.flash_settings.duration_out_of_range",
            min: SiteSetting::FLASH_TOAST_DURATION_MIN_MS,
            max: SiteSetting::FLASH_TOAST_DURATION_MAX_MS),
          :alert
        )
        return
      end

      SiteSetting.set("flash_toast_duration_ms", ms.to_s)
      log_admin_action(action: "update_flash_toast_duration_ms", changes_data: { duration_ms: ms })
      @duration_ms = SiteSetting.flash_toast_duration_ms
      respond_flash_settings_update(t("admin.flash_settings.updated"), :notice)
    end

    def test
      kind = params[:kind].to_s
      unless %w[notice alert warning info].include?(kind)
        @admin_flash_settings_message = t("admin.flash_settings.invalid_test_kind")
        @admin_flash_settings_variant = :alert
        respond_to do |format|
          format.html { redirect_to admin_flash_settings_path, alert: @admin_flash_settings_message }
          format.turbo_stream { render :flash_settings_flash_only }
        end
        return
      end

      msg = t("admin.flash_settings.test_message.#{kind}")
      variant = %w[notice info].include?(kind) ? :notice : :alert

      respond_to do |format|
        format.html do
          flash[kind.to_sym] = msg
          redirect_to admin_flash_settings_path
        end
        format.turbo_stream do
          @admin_flash_settings_message = msg
          @admin_flash_settings_variant = variant
          render :flash_settings_flash_only
        end
      end
    end

    private

    def load_flash_settings_show
      @duration_ms = SiteSetting.flash_toast_duration_ms
    end

    def respond_flash_settings_update(message, variant)
      @admin_flash_settings_message = message
      @admin_flash_settings_variant = variant
      respond_to do |format|
        format.html do
          if variant == :notice
            redirect_to admin_flash_settings_path, notice: message
          else
            redirect_to admin_flash_settings_path, alert: message
          end
        end
        format.turbo_stream { render :flash_settings_refresh }
      end
    end
  end
end
