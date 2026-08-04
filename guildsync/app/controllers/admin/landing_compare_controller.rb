# frozen_string_literal: true

module Admin
  class LandingCompareController < BaseController
    LANDING_COMPARE_EDIT_MAIN_FRAME = "admin_landing_compare_main"

    def edit
      assign_landing_compare_edit
      return render("landing_compare_edit_frame", layout: false) if request.headers["Turbo-Frame"] == LANDING_COMPARE_EDIT_MAIN_FRAME
    end

    def update
      form = LandingCompare::Form.new(params)
      if form.save
        log_admin_action(action: "update_landing_compare", changes_data: { updated: true })
        assign_landing_compare_edit
        @admin_landing_compare_message = t("admin.landing_compare.updated")
        @admin_landing_compare_variant = :notice
        respond_to do |format|
          format.html { redirect_to admin_edit_landing_compare_path, notice: @admin_landing_compare_message }
          format.turbo_stream { render :landing_compare_refresh }
        end
      else
        msg = form.errors.full_messages.to_sentence.presence || t("admin.landing_compare.invalid")
        respond_to do |format|
          format.html { redirect_to admin_edit_landing_compare_path, alert: msg }
          format.turbo_stream { redirect_to admin_edit_landing_compare_path, alert: msg, status: :see_other }
        end
      end
    end
    private

    def assign_landing_compare_edit
      # Production DB is CMS source of truth; deploy does not import YAML. If comparison tables
      # were never seeded (empty DB, failed one-time migration, etc.), create catalog defaults here
      # so admins can edit without running ad-hoc migrations.
      bootstrap_landing_compare_defaults_if_empty!

      @tables = LandingComparisonTable.order(:position).includes(:landing_comparison_rows)
      @section_title_field = SiteSetting.find_by(key: "landing_compare_section_title")&.value.to_s
    end

    def bootstrap_landing_compare_defaults_if_empty!
      return unless LandingComparisonTable.count.zero? && LandingComparisonRow.count.zero?

      LandingCompare::SeedDefaults.seed!
    end
  end
end
