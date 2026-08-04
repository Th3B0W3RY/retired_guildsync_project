# frozen_string_literal: true

module Admin
  class SoftDeletedRecordsController < BaseController
    def index
      @query = sanitize_search_input(params[:q])
      raw_filter = params[:record_filter].presence
      if raw_filter.present? && SoftDeletedRecordRegistry.fetch(raw_filter).nil?
        redirect_to admin_soft_deleted_records_path(q: params[:q].presence),
          alert: I18n.t("admin.soft_deleted_records.index.invalid_record_filter")
        return
      end

      @record_filter = raw_filter
      @record_type_options = SoftDeletedRecordRegistry.type_options
      @records = load_deleted_records
    end

    def restore
      record = find_deleted_record
      unless record.soft_delete_restorable?
        redirect_to admin_soft_deleted_records_path(filtered_params),
          alert: I18n.t(
            "admin.soft_deleted_records.flash.outside_retention",
            months: (SoftDeletable::RETENTION_PERIOD / 1.month).to_i
          )
        return
      end

      label = record.soft_delete_display_name
      record.restore!

      log_admin_action(
        action: "restore_soft_deleted_record",
        record: record,
        changes_data: { record_type: record.class.name, restored: true }
      )

      redirect_to admin_soft_deleted_records_path(filtered_params),
        notice: I18n.t("admin.soft_deleted_records.flash.restored", label: label)
    end

    def purge
      record = find_deleted_record
      label = record.soft_delete_display_name
      purge_reason = params[:purge_reason].to_s.strip
      purge_confirmation = params[:purge_confirmation].to_s.strip

      unless purge_confirmation_matches?(purge_confirmation, label) && purge_reason.present?
        redirect_to admin_soft_deleted_records_path(filtered_params),
          alert: I18n.t("admin.soft_deleted_records.flash.purge_confirmation_failed", label: label)
        return
      end

      record.destroy!

      log_admin_action(
        action: "purge_soft_deleted_record",
        changes_data: {
          record_type: record.class.name,
          record_id: record.id,
          label: label,
          purge_reason: purge_reason
        }
      )

      redirect_to admin_soft_deleted_records_path(filtered_params),
        notice: I18n.t("admin.soft_deleted_records.flash.purged", label: label)
    end

    private

    def load_deleted_records
      selected_classes = selected_record_classes

      records = selected_classes.flat_map do |klass|
        scope = klass.deleted_within_retention_period.order(deleted_at: :desc)
        @query.present? ? scope.to_a : scope.limit(100).to_a
      end

      if @query.present?
        downcased_query = @query.downcase
        records.select! { |record| record.soft_delete_search_text.downcase.include?(downcased_query) }
      end

      records.sort_by { |record| [ record.deleted_at || Time.at(0), record.id ] }.reverse.first(200)
    end

    def selected_record_classes
      return SoftDeletedRecordRegistry.classes if @record_filter.blank?

      klass = SoftDeletedRecordRegistry.fetch(@record_filter)
      return [ klass ] if klass

      []
    end

    def find_deleted_record
      klass = SoftDeletedRecordRegistry.fetch(params[:record_type])
      raise ActiveRecord::RecordNotFound if klass.nil?

      klass.deleted.find(params[:id])
    end

    def filtered_params
      {
        q: params[:q].presence,
        record_filter: params[:record_filter].presence
      }.compact
    end

    def purge_confirmation_matches?(provided_confirmation, expected_label)
      return false if provided_confirmation.blank? || expected_label.blank?
      return false unless provided_confirmation.bytesize == expected_label.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided_confirmation, expected_label)
    end
  end
end
