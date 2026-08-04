# frozen_string_literal: true

# Alliance routes require a non-free, non-trial plan. Default User + Guild factories
# often leave the owner on the Free plan; use these helpers in request specs.
module AllianceRequestHelpers
  def alliance_spec_paid_plan
    @alliance_spec_paid_plan ||= begin
      plan = PricingPlan.find_or_create_by!(name: "RSpec Alliance Access Paid") do |p|
        p.price = 22
        p.price_display = "$22"
        p.period = "per month"
        p.max_guilds = 15
        p.max_members_per_guild = 200
        p.active = true
        p.display_order = 55
        p.can_create_alliance = true
      end
      # find_or_create can return an older row with nil/zero price (treated as free for alliance gates).
      plan.update!(price: 22) if plan.price.nil? || plan.price.zero?
      plan.update!(can_create_alliance: true) unless plan.can_create_alliance?
      plan
    end
  end

  # Paid active subscription so alliance before_actions allow access.
  def create_alliance_paid_user!(*traits)
    u = create(:user, *traits, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: alliance_spec_paid_plan, status: :active, started_at: Time.current)
    u.reload
  end
end

RSpec.configure do |config|
  config.include AllianceRequestHelpers, type: :request
  config.include AllianceRequestHelpers, type: :channel
end
