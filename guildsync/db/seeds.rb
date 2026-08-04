# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The data here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require Rails.root.join("lib/pricing_plan_initializer")

puts "Ensuring pricing plans (limits + Stripe from ENV; card copy persists after first create / admin edits)..."
PricingPlanInitializer.ensure_plans_exist!
puts "Pricing plans OK."

if Rails.env.development?
  load Rails.root.join("db/seeds/landing_marketing_cms_development.rb")
end
