# frozen_string_literal: true

# Default marketing feature bullets for pricing cards (shown on site + admin).
# Used when a plan row is first created. After that, admin edits persist across deploys
# (see PricingPlanInitializer — it does not overwrite these on existing rows).
module PricingPlanCardDefaults
  FEATURES_BY_PLAN_NAME = {
    "Free" => [
      "1 Guild",
      "75 Users",
      "Guild System",
      "Event, Polls, Loot Rolls",
      "Guild Discord Role Syncing",
      "Member Leaderboard"
    ],
    "Basic" => [
      "Unlimited Guilds",
      "Unlimited Users",
      "Guild System",
      "Alliance System",
      "Event, Polls, Loot Rolls",
      "Guild Discord Role Syncing",
      "Activity Feed",
      "Member Leaderboard",
      "Warnings System(for members)",
      "Discord Bot Message System"
    ],
    "Upgraded" => [
      "Unlimited Guilds",
      "Unlimited Users",
      "Guild System",
      "Alliance System",
      "Event, Polls, Loot Rolls",
      "Guild Discord Role Syncing",
      "Custom GuildSync Roles",
      "Activity Feed",
      "Member Leaderboard",
      "Warnings System(for members)",
      "Discord Bot Message System",
      "AI Gear Screenshot Scanning(5k requests)",
      "Guild Document System",
      "20 GB Image Storage"
    ],
    "Elite" => [
      "Unlimited Guilds",
      "Unlimited Users",
      "Guild System",
      "Alliance System",
      "Event, Polls, Loot Rolls",
      "Guild Discord Role Syncing",
      "Custom GuildSync Roles",
      "Activity Feed",
      "Member Leaderboard",
      "Warnings System(for members)",
      "Discord Bot Message System",
      "AI Gear Screenshot Scanning(10k requests)",
      "Guild Document System",
      "30 GB Image Storage",
      "Access To Beta Features In Development"
    ]
  }.freeze
end
