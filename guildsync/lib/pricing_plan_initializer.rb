# frozen_string_literal: true

require_relative "pricing_plan_card_defaults"

class PricingPlanInitializer
  # Attributes synced on every boot for existing plans (product limits + Stripe IDs from ENV).
  # Card/marketing fields (features, copy, prices on card, order, etc.) are set only when the row is created.
  SYNC_ATTRIBUTES = %i[
    max_guilds
    max_members_per_guild
    max_polls
    max_loot_rolls
    max_events
    can_create_alliance
  ].freeze

  # Free + 3 paid plans: Basic, Upgraded, Elite. Display order: Free (0), Basic (1), Upgraded (2), Elite (3).
  REQUIRED_PLANS = [
    {
      name: "Free",
      price: 0,
      price_display: "$0",
      period: "forever",
      max_guilds: 1,
      max_members_per_guild: 75,
      max_polls: 3,
      max_loot_rolls: 2,
      max_events: 3,
      active: true,
      can_create_alliance: false,
      description: "Limited features to get started",
      popular: false,
      display_order: 0,
      cta_text: "Get Started",
      cta_path: "/sign_up",
      stripe_price_id: nil
    },
    {
      name: "Basic",
      price: 12,
      price_display: "$12",
      period: "per month",
      max_guilds: nil,
      max_members_per_guild: 75,
      max_polls: 25,
      max_loot_rolls: 20,
      max_events: 25,
      active: true,
      can_create_alliance: true,
      description: "Essential features for small groups",
      popular: true,
      display_order: 1,
      cta_text: "Start 14-Day Free Trial",
      cta_path: "/sign_up",
      stripe_price_id: nil
    },
    {
      name: "Upgraded",
      price: 16,
      price_display: "$16",
      period: "per month",
      max_guilds: nil,
      max_members_per_guild: nil,
      max_polls: 100,
      max_loot_rolls: 80,
      max_events: 100,
      active: true,
      can_create_alliance: true,
      description: "More capacity and options",
      popular: false,
      display_order: 2,
      cta_text: "Subscribe",
      cta_path: "/sign_up",
      stripe_price_id: nil
    },
    {
      name: "Elite",
      price: 25,
      price_display: "$25",
      period: "per month",
      max_guilds: nil,
      max_members_per_guild: 500,
      max_polls: nil,
      max_loot_rolls: nil,
      max_events: nil,
      active: true,
      can_create_alliance: true,
      description: "Maximum capacity and priority support",
      popular: false,
      display_order: 3,
      cta_text: "Subscribe",
      cta_path: "/sign_up",
      stripe_price_id: nil
    }
  ].map do |attrs|
    name = attrs[:name]
    attrs.merge(features: PricingPlanCardDefaults::FEATURES_BY_PLAN_NAME[name] || [])
  end.freeze

  def self.ensure_plans_exist!
    return true unless defined?(PricingPlan)
    return true unless PricingPlan.table_exists?

    migrate_standard_to_basic_if_present!

    plan_attrs_list = REQUIRED_PLANS.map { |attrs| attrs.merge(stripe_attrs_from_env(attrs[:name])) }

    plan_attrs_list.each do |attrs|
      created = false
      plan = PricingPlan.find_or_create_by!(name: attrs[:name]) do |p|
        created = true
        p.assign_attributes(build_full_create_attributes(attrs))
      end

      next if created

      sync = attrs.slice(*SYNC_ATTRIBUTES)
      sync.merge!(stripe_attrs_from_env(attrs[:name]))
      plan.assign_attributes(sync)
      plan.save! if plan.has_changes_to_save?
    end

    required_names = REQUIRED_PLANS.map { |p| p[:name] }
    PricingPlan.where.not(name: required_names).update_all(active: false)

    puts "  ✓ Pricing Plans: OK"
    true
  rescue => e
    puts "  ✗ Pricing Plans: FAILED - #{e.message}"
    false
  end

  def self.build_full_create_attributes(attrs)
    attrs.slice(
      :name, :price, :price_display, :period, :max_guilds, :max_members_per_guild,
      :max_polls, :max_loot_rolls, :max_events, :active, :can_create_alliance,
      :description, :popular, :features, :display_order, :cta_text, :cta_path,
      :stripe_price_id, :stripe_price_id_annual, :price_display_annual
    )
  end

  def self.stripe_attrs_from_env(name)
    case name
    when "Basic"
      {
        stripe_price_id: ENV["STRIPE_BASIC_PRICE_ID"].presence || ENV["STRIPE_STANDARD_PRICE_ID"].presence,
        stripe_price_id_annual: ENV["STRIPE_BASIC_PRICE_ID_ANNUAL"].presence,
        price_display_annual: ENV["STRIPE_BASIC_PRICE_DISPLAY_ANNUAL"].presence
      }.compact
    when "Upgraded"
      {
        stripe_price_id: ENV["STRIPE_UPGRADED_PRICE_ID"].presence,
        stripe_price_id_annual: ENV["STRIPE_UPGRADED_PRICE_ID_ANNUAL"].presence,
        price_display_annual: ENV["STRIPE_UPGRADED_PRICE_DISPLAY_ANNUAL"].presence
      }.compact
    when "Elite"
      {
        stripe_price_id: ENV["STRIPE_ELITE_PRICE_ID"].presence,
        stripe_price_id_annual: ENV["STRIPE_ELITE_PRICE_ID_ANNUAL"].presence,
        price_display_annual: ENV["STRIPE_ELITE_PRICE_DISPLAY_ANNUAL"].presence
      }.compact
    else
      {}
    end
  end

  def self.migrate_standard_to_basic_if_present!
    standard = PricingPlan.find_by(name: "Standard")
    return unless standard

    basic_template = REQUIRED_PLANS.find { |p| p[:name] == "Basic" }
    return unless basic_template

    sync = basic_template.slice(*SYNC_ATTRIBUTES)
    standard.update!(
      {
        name: "Basic",
        price: basic_template[:price],
        price_display: basic_template[:price_display],
        period: basic_template[:period],
        description: basic_template[:description],
        popular: basic_template[:popular],
        display_order: basic_template[:display_order],
        features: basic_template[:features],
        cta_text: basic_template[:cta_text],
        cta_path: basic_template[:cta_path],
        stripe_price_id: ENV["STRIPE_BASIC_PRICE_ID"].presence || ENV["STRIPE_STANDARD_PRICE_ID"].presence || standard.stripe_price_id
      }.merge(sync)
    )
  end
  private_class_method :migrate_standard_to_basic_if_present!, :build_full_create_attributes, :stripe_attrs_from_env
end
