# frozen_string_literal: true

module Admin
  # Turbo links inside <turbo-frame id="admin_dashboard_index_main"> default to that frame.
  # Marketing CMS controllers did not return a matching frame body, which surfaced as the
  # English Turbo error "Content missing" in the admin UI.
  module TurboDashboardFrame
    extend ActiveSupport::Concern

    private

    def respond_with_dashboard_frame(template)
      return false unless request.headers["Turbo-Frame"] == Admin::DashboardController::DASHBOARD_INDEX_MAIN_FRAME

      render(template, layout: false)
      true
    end
  end
end
