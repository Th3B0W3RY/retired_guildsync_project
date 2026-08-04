# frozen_string_literal: true

module Admin
  module SystemMonitoringHelper
    # JSON-friendly blob for Stimulus (metric card labels + chart dataset labels + status strings).
    def admin_system_monitoring_stimulus_i18n
      {
        click_refresh_to_load: I18n.t("admin.system_monitoring.js.click_refresh_to_load"),
        error_loading: I18n.t("admin.system_monitoring.js.error_loading"),
        error_http: I18n.t("admin.system_monitoring.js.error_http"),
        updated_at: I18n.t("admin.system_monitoring.js.updated_at"),
        metric_rows: I18n.t("admin.system_monitoring.metric_rows"),
        charts: I18n.t("admin.system_monitoring.charts")
      }
    end
  end
end
