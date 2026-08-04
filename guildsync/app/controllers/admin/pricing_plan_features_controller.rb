# frozen_string_literal: true

module Admin
  class PricingPlanFeaturesController < BaseController
    PRICING_PLAN_FEATURES_EDIT_MAIN_FRAME = "admin_pricing_plan_features_main"

    def edit
      @plans = PricingPlan.order(:display_order, :id)
      return render("pricing_plan_features_edit_frame", layout: false) if request.headers["Turbo-Frame"] == PRICING_PLAN_FEATURES_EDIT_MAIN_FRAME
    end

    def update
      raw = params[:pricing_plans]
      unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)
        respond_pricing_plan_features_failure(t("admin.pricing_plan_features.invalid_payload"))
        return
      end

      updated_ids = []
      PricingPlan.transaction do
        raw.each do |id_str, attrs|
          id = id_str.to_s.to_i
          next if id <= 0

          plan = PricingPlan.lock.find_by(id: id)
          next unless plan

          hash = attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs.to_h
          text = hash["features_text"] || hash[:features_text]
          lines = text.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)

          price_display = extract_param_str(hash, "price_display")
          if price_display.blank?
            plan.errors.add(:price_display, :blank)
            raise ActiveRecord::RecordInvalid, plan
          end

          price_display_annual = extract_param_str(hash, "price_display_annual")
          monthly_raw = extract_param_str(hash, "price_monthly")
          new_price =
            if monthly_raw.blank?
              plan.price
            else
              parse_monthly_decimal(monthly_raw)
            end

          name = extract_param_str(hash, "name")
          if name.blank?
            plan.errors.add(:name, :blank)
            raise ActiveRecord::RecordInvalid, plan
          end

          period = extract_param_str(hash, "period")
          if period.blank?
            plan.errors.add(:period, :blank)
            raise ActiveRecord::RecordInvalid, plan
          end

          description = hash["description"] || hash[:description]
          display_order_raw = extract_param_str(hash, "display_order")
          display_order =
            begin
              if display_order_raw.blank?
                plan.display_order
              else
                Integer(display_order_raw, 10)
              end
            rescue ArgumentError, TypeError
              plan.errors.add(:display_order, :not_an_integer)
              raise ActiveRecord::RecordInvalid, plan
            end

          attrs = {
            name: name,
            period: period,
            description: description,
            display_order: display_order,
            features: lines,
            price_display: price_display,
            price_display_annual: price_display_annual.presence,
            price: new_price
          }
          if hash.key?("entitlements") || hash.key?(:entitlements)
            attrs[:feature_entitlements] = build_feature_entitlements_from_params(hash)
          end
          if hash.key?("popular") || hash.key?(:popular)
            attrs[:popular] = param_truthy?(hash, "popular")
          end
          if hash.key?("active") || hash.key?(:active)
            attrs[:active] = param_truthy?(hash, "active")
          end
          plan.update!(attrs)
          updated_ids << id
        end
      end

      log_admin_action(
        action: "update_pricing_plan_features",
        changes_data: { updated_plan_ids: updated_ids }
      )

      @plans = PricingPlan.order(:display_order, :id)
      @admin_pricing_plan_features_message = t("admin.pricing_plan_features.updated")
      @admin_pricing_plan_features_variant = :notice
      respond_to do |format|
        format.html { redirect_to admin_edit_pricing_plan_features_path, notice: @admin_pricing_plan_features_message }
        format.turbo_stream { render :pricing_plan_features_refresh }
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_pricing_plan_features_failure(
        t("admin.pricing_plan_features.validation_error", message: e.record.errors.full_messages.to_sentence)
      )
    rescue ArgumentError
      respond_pricing_plan_features_failure(t("admin.pricing_plan_features.invalid_monthly_price"))
    end

    private

    def respond_pricing_plan_features_failure(alert_message)
      respond_to do |format|
        format.html { redirect_to admin_edit_pricing_plan_features_path, alert: alert_message }
        format.turbo_stream do
          redirect_to admin_edit_pricing_plan_features_path, alert: alert_message, status: :see_other
        end
      end
    end

    def extract_param_str(hash, key)
      (hash[key] || hash[key.to_sym]).to_s.strip
    end

    def parse_monthly_decimal(raw)
      normalized = raw.to_s.tr(",", ".").gsub(/[^\d.]/, "")
      raise ArgumentError if normalized.blank?

      BigDecimal(normalized)
    end

    def param_truthy?(hash, key)
      v = hash[key] || hash[key.to_sym]
      ActiveModel::Type::Boolean.new.cast(v)
    end

    def build_feature_entitlements_from_params(hash)
      ent_raw = hash["entitlements"] || hash[:entitlements]
      unless ent_raw.is_a?(ActionController::Parameters) || ent_raw.is_a?(Hash)
        return {}
      end

      h = ent_raw.respond_to?(:to_unsafe_h) ? ent_raw.to_unsafe_h.stringify_keys : ent_raw.stringify_keys
      PlanEntitlementService.feature_flag_keys.each_with_object({}) do |key, acc|
        k = key.to_s
        next unless h.key?(k)

        acc[k] = ActiveModel::Type::Boolean.new.cast(h[k])
      end
    end
  end
end
