# frozen_string_literal: true

module Admin
  class SiteSettingsController < BaseController
    RELEASE_NOTES_MAIN_FRAME = "admin_release_notes_main"

    def release_notes
      @release_notes_url = SiteSetting.release_notes_url
      render("release_notes_frame", layout: false) if request.headers["Turbo-Frame"] == RELEASE_NOTES_MAIN_FRAME
    end

    def update_release_notes
      url = support_pages_url_param

      SiteSetting.set("release_notes_url", url)
      log_admin_action(action: "update_release_notes_url", changes_data: { url: url })
      @release_notes_url = SiteSetting.release_notes_url
      @admin_release_notes_message = t("roadmap.admin.release_notes.updated")
      @admin_release_notes_variant = :notice
      respond_to do |format|
        format.html { redirect_to admin_release_notes_settings_path, notice: @admin_release_notes_message }
        format.turbo_stream { render :release_notes_refresh }
      end
    rescue Guildsync::ExternalRedirectUrl::Invalid
      redirect_invalid_release_notes_url
    end

    private

    def support_pages_url_param
      Guildsync::ExternalRedirectUrl.build!(params[:release_notes_url])
    end

    def redirect_invalid_release_notes_url
      msg = t("roadmap.admin.release_notes.invalid_url")
      respond_to do |format|
        format.html { redirect_to admin_release_notes_settings_path, alert: msg }
        format.turbo_stream { redirect_to admin_release_notes_settings_path, alert: msg, status: :see_other }
      end
    end
  end
end
