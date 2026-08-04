# frozen_string_literal: true

module Admin
  class ErrorBatchReportsController < BaseController
    PER_PAGE = 30

    def index
      @reports = ErrorBatchReport.recent.limit(PER_PAGE)
    end

    def show
      @report = ErrorBatchReport.find(params[:id])
    end

    def run_now
      ErrorBatchReportJob.perform_later("admin:#{current_admin_email}")
      log_admin_action(action: "trigger_error_batch_report")
      notice = t("admin.error_batch_reports.flash.queued")
      respond_to do |format|
        format.html { redirect_to admin_error_batch_reports_path, notice: notice }
        format.turbo_stream do
          @notice = notice
          render :run_now
        end
      end
    end
  end
end
