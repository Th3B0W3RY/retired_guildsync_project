# frozen_string_literal: true

module Admin
  class AuditLogsController < BaseController
    AUDIT_LOGS_RESULTS_FRAME = "admin_audit_logs_results"
    AUDIT_LOGS_SHOW_MAIN_FRAME = "admin_audit_logs_show_main"

    def index
      @audit_logs = AdminAuditLog.recent.limit(100)
      @audit_logs = @audit_logs.where(admin_email: params[:admin_email]) if params[:admin_email].present?
      @audit_logs = @audit_logs.where(controller: params[:controller_name]) if params[:controller_name].present?
      @audit_logs = @audit_logs.where(record_type: params[:record_type]) if params[:record_type].present?
      if request.headers["Turbo-Frame"] == AUDIT_LOGS_RESULTS_FRAME
        render "audit_logs_results_frame", layout: false
      end
    end

    def show
      @audit_log = AdminAuditLog.find(params[:id])
      return render("audit_logs_show_frame", layout: false) if request.headers["Turbo-Frame"] == AUDIT_LOGS_SHOW_MAIN_FRAME
    end
  end
end

