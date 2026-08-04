# frozen_string_literal: true

FactoryBot.define do
  factory :pricing_plan do
    sequence(:name) { |n| "Plan #{n}" }
    price_display { "$0" }
    period { "forever" }
    max_guilds { 1 }
    max_members_per_guild { 25 }
    active { true }

    # For known seed-plan names (Free, Basic, Upgraded, Elite) use find_or_initialize_by to
    # avoid uniqueness errors when seeds have already created these plans.
    # All instance attributes are applied unconditionally so that tests can override any column
    # (including setting stripe_price_id to nil).  Transactional fixtures roll back changes
    # after each example so the seeded plan is restored for the next test.
    SEED_PLAN_NAMES = %w[Free Basic Upgraded Elite].freeze

    to_create do |instance|
      if SEED_PLAN_NAMES.include?(instance.name)
        plan = PricingPlan.find_or_initialize_by(name: instance.name)
        %i[price price_display period max_guilds max_members_per_guild active display_order
           stripe_price_id stripe_price_id_annual popular cta_text cta_path description].each do |attr|
          plan.send(:"#{attr}=", instance.send(attr))
        end
        plan.save!
        # Wire the factory-built instance to the persisted plan so that subsequent FactoryBot
        # after hooks and in-test `.update` calls behave like working with a real persisted record.
        instance.id = plan.id
        instance.instance_variable_set(:@new_record, false)
        instance.clear_changes_information
        plan
      else
        instance.save!
        instance
      end
    end
  end
end

