# frozen_string_literal: true

module Admin
  class SystemMonitoringController < BaseController
    SYSTEM_MONITORING_MAIN_FRAME = "admin_system_monitoring_main"

    def show
      # HTML dashboard; metrics load only when the user clicks Refresh (Stimulus + bundled Chart.js).
      return render("system_monitoring_show_frame", layout: false) if request.headers["Turbo-Frame"] == SYSTEM_MONITORING_MAIN_FRAME
    end

    def metrics
      data = Monitoring::Collector.call
      render json: data
    end
  end
end
