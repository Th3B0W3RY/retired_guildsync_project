# frozen_string_literal: true

FactoryBot.define do
  factory :guild do
    association :owner, factory: :user
    sequence(:name) { |n| "Guild #{n}" }
    description { "A test guild" }

    after(:build) do |guild|
      # Ensure owner has a subscription
      unless guild.owner.current_subscription
        plan = PricingPlan.find_or_create_by!(name: "Test Plan") do |p|
          # Non-zero price so PricingPlan#free? is false (alliance and other paid-only gates use free?, not plan name).
          p.price = 1
          p.price_display = "$1"
          p.period = "forever"
          p.max_guilds = 10
          p.max_members_per_guild = 100
          p.active = true
        end
        plan.update!(price: 1) if plan.price.nil? || plan.price.zero?
        create(:subscription, user: guild.owner, pricing_plan: plan)
      end
    end

    trait :archived do
      archived_at { 2.days.ago }
      scheduled_purge_at { 1.year.from_now }
    end

    # After creating the guild, add the owner as a member (matching controller behavior)
    # Also ensure guild has at least one game (required by controller)
    after(:create) do |guild|
      unless guild.guild_members.exists?(user_id: guild.owner_id)
        guild.guild_members.create!(user: guild.owner, role: :owner, status: :active)
      end
      
      # Ensure guild has at least one game (required by controller validation)
      if guild.games.empty?
        game = Game.find_or_create_by!(name: "Test Game", slug: "test-game") do |g|
          g.description = "Default test game"
          g.active = true
          g.ocr_config = {}
        end
        guild.guild_games.create!(game: game, primary: true)
      end
    end
  end
end

