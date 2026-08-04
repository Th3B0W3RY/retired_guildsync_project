# frozen_string_literal: true

class PlanEntitlementService
  PATH = Rails.root.join("config/plan_entitlements.yml")

  class << self
    def matrix
      @matrix ||= YAML.load_file(PATH).transform_keys { |k| k.to_s.downcase }
    end

    # All boolean entitlement keys across tiers (for admin UI + overrides).
    def feature_flag_keys
      @feature_flag_keys ||= matrix.values.flat_map(&:keys).map(&:to_s).uniq.sort.freeze
    end

    # YAML row for plan name, merged with per-plan DB overrides on pricing_plans.feature_entitlements.
    def entitlement_row_for(pricing_plan)
      return {} unless pricing_plan

      tier = pricing_plan.name.to_s.downcase.strip
      base = matrix[tier] || {}
      overrides = pricing_plan.try(:feature_entitlements)
      overrides = {} if overrides.blank?
      ov = overrides.stringify_keys.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
      base.merge(ov)
    end

    def allowed?(user, feature)
      return false unless user
      fn = feature.to_s.downcase
      plan = user.current_plan
      return false unless plan

      row = entitlement_row_for(plan)
      if fn == "beta_features"
        return true if user.respond_to?(:beta_features_enabled) && user.beta_features_enabled
        return row["beta_features"] == true
      end
      row[fn] == true
    end
  end
end
