# frozen_string_literal: true

module LandingCompare
  # Single source of truth for default comparison rows. Copy reflects GuildSync product
  # capabilities vs positioning on [Guild Manager](https://guildmanager.app/) (events, DKP/loot,
  # recruitment, Discord, audit, API, multi-game) and a conservative middle column for GuildSpire
  # where public positioning is limited ([guildspire.com](https://www.guildspire.com/)).
  module Catalog
    # Each row: i18n key + English default label for DB seed + booleans for competitor columns
    # (true = green check, false = red X). GuildSync column is always all true in seeds.
    # Production pricing tiers: see PricingPlanInitializer (Basic @ $12 is the “essential” paid starter).
    # After seed/migrate, admins override via Admin → GuildSync vs Competitors (DB wins on the site).
    ROWS = [
      { key: "rapid_user_feedback", label: "Rapid, user-feedback-based development",
        guild_manager: false, guild_spire: false, typical: false },
      { key: "unlimited_guilds", label: "Unlimited guilds",
        guild_manager: false, guild_spire: false, typical: false },
      { key: "starter_basic_plan_value", label: "Basic plan — essential features without premium-only pricing",
        guild_manager: false, guild_spire: false, typical: false },
      { key: "multi_game_dashboard", label: "Multi-game guild dashboard",
        guild_manager: true, guild_spire: true, typical: false },
      { key: "events_scheduling", label: "Events, RSVPs & scheduling",
        guild_manager: true, guild_spire: true, typical: false },
      { key: "loot_rolls_distribution", label: "Loot rolls & fair distribution",
        guild_manager: true, guild_spire: true, typical: false },
      { key: "recruitment_applications", label: "Recruitment & applications",
        guild_manager: true, guild_spire: true, typical: false },
      { key: "discord_integration", label: "Discord bot & integration",
        guild_manager: true, guild_spire: true, typical: false },
      { key: "member_analytics", label: "Member analytics & insights",
        guild_manager: true, guild_spire: true, typical: false },
      { key: "audit_history", label: "Long-term audit & activity history",
        guild_manager: true, guild_spire: false, typical: false },
      { key: "guild_documents_storage", label: "Guild documents & file storage",
        guild_manager: true, guild_spire: false, typical: false },
      { key: "polls_community_votes", label: "Polls & community votes",
        guild_manager: true, guild_spire: true, typical: false },
      { key: "public_roadmap_voting", label: "Public roadmap & feature voting",
        guild_manager: false, guild_spire: false, typical: false },
      { key: "api_access", label: "API access",
        guild_manager: true, guild_spire: false, typical: false },
      { key: "export_data_backup", label: "Export & data backup",
        guild_manager: true, guild_spire: false, typical: false },
      { key: "custom_role_system", label: "Custom Role System",
        guild_manager: false, guild_spire: false, typical: false }
    ].freeze

    FEAT_KEYS = ROWS.map { |r| r[:key] }.freeze

    class << self
      def label_for_key(key)
        ROWS.find { |r| r[:key] == key }&.fetch(:label) || key.to_s.humanize
      end

      def competitor_included?(table_position, key)
        row = ROWS.find { |r| r[:key] == key.to_s }
        return false unless row

        case table_position
        when 0 then row[:guild_manager]
        when 1 then row[:guild_spire]
        when 2 then row[:typical]
        else false
        end
      end

      def rebuild_rows_for_table!(table)
        table.landing_comparison_rows.delete_all
        ROWS.each_with_index do |row, idx|
          table.landing_comparison_rows.create!(
            position: idx,
            feature_label: row[:label],
            guildsync_included: true,
            competitor_included: competitor_included?(table.position, row[:key])
          )
        end
      end
    end
  end
end
