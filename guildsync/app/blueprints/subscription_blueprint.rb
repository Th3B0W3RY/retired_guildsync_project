# frozen_string_literal: true

# Exposes subscription state for the account owner only (UserBlueprint :private).
# Do not add Stripe identifiers or internal billing timestamps here.
class SubscriptionBlueprint < Blueprinter::Base
  identifier :id

  fields :status, :trial_ends_at, :expires_at, :canceled_at

  association :pricing_plan, blueprint: PricingPlanBlueprint
end
