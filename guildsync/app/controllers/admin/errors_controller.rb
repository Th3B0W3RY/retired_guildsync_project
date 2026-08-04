# frozen_string_literal: true

module Admin
  class ErrorsController < BaseController
    PER_PAGE = 25
    ERRORS_INDEX_MAIN_FRAME = "admin_errors_index_main"
    ERRORS_SHOW_MAIN_FRAME = "admin_errors_show_main"

    def index
      load_errors_index_assigns
      if request.headers["Turbo-Frame"] == ERRORS_INDEX_MAIN_FRAME
        render "errors_index_main_frame", layout: false
      end
    end

    def show
      @error = ErrorLog.find(params[:id])
      if request.headers["Turbo-Frame"] == ERRORS_SHOW_MAIN_FRAME
        render "errors_show_frame", layout: false
      end
    end

    def resolve
      @error = ErrorLog.find(params[:id])
      @error.resolve!(current_admin_email)
      log_admin_action(action: "resolve_error", record: @error)
      notice = t("admin.errors.flash.resolved")
      respond_to do |format|
        format.html { redirect_to admin_error_path(@error), notice: notice }
        format.turbo_stream do
          @error.reload
          @admin_error_show_flash_message = notice
          @admin_error_show_flash_variant = :notice
          render :error_show_refresh
        end
      end
    end

    def destroy
      @error = ErrorLog.find(params[:id])
      @error.destroy!
      log_admin_action(action: "delete_error", record: @error)
      notice = t("admin.errors.flash.deleted")
      respond_to do |format|
        format.html { redirect_to admin_errors_path, notice: notice }
        format.turbo_stream do
          if referer_is_errors_index?
            assign_errors_index_refresh(notice, :notice)
            render :errors_index_refresh
          else
            redirect_to admin_errors_path, notice: notice, status: :see_other
          end
        end
      end
    end

    def bulk_action
      ids = Array(params[:error_ids]).map(&:to_i).reject(&:zero?)
      action = params[:bulk_action].to_s

      if ids.empty?
        assign_errors_index_refresh(t("admin.errors.flash.select_one"), :alert)
        respond_to do |format|
          format.html { redirect_to admin_errors_path, alert: t("admin.errors.flash.select_one") }
          format.turbo_stream { render :errors_index_refresh }
        end
        return
      end

      records = ErrorLog.where(id: ids)

      case action
      when "resolve"
        records.update_all(resolved_at: Time.current, resolved_by: current_admin_email)
        log_admin_action(action: "bulk_resolve_errors", changes_data: { count: records.count, ids: ids })
        notice = t("admin.errors.flash.bulk_resolved", count: records.count)
        assign_errors_index_refresh(notice, :notice)
        respond_to do |format|
          format.html { redirect_to admin_errors_path, notice: notice }
          format.turbo_stream { render :errors_index_refresh }
        end
      when "delete"
        count = records.count
        records.destroy_all
        log_admin_action(action: "bulk_delete_errors", changes_data: { count: count, ids: ids })
        notice = t("admin.errors.flash.bulk_deleted", count: count)
        assign_errors_index_refresh(notice, :notice)
        respond_to do |format|
          format.html { redirect_to admin_errors_path, notice: notice }
          format.turbo_stream { render :errors_index_refresh }
        end
      else
        assign_errors_index_refresh(t("admin.errors.flash.unknown_bulk_action"), :alert)
        respond_to do |format|
          format.html { redirect_to admin_errors_path, alert: t("admin.errors.flash.unknown_bulk_action") }
          format.turbo_stream { render :errors_index_refresh }
        end
      end
    end

    private

    def load_errors_index_assigns
      @unresolved = ErrorLog.unresolved.recent.limit(PER_PAGE)
      @resolved   = ErrorLog.resolved.recent.limit(PER_PAGE)
    end

    def assign_errors_index_refresh(message, variant)
      load_errors_index_assigns
      @admin_errors_message = message
      @admin_errors_flash_variant = variant
    end

    def referer_is_errors_index?
      ref = request.referer
      return false if ref.blank?

      URI.parse(ref).path == admin_errors_path
    rescue URI::InvalidURIError
      false
    end
  end
end
