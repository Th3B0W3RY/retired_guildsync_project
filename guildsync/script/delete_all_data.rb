# frozen_string_literal: true

# Script to safely delete all user data from the database
# This preserves pricing plans and other seed data
#
# Usage: rails runner script/delete_all_data.rb

begin
  require "dotenv"
  env_file = File.expand_path("../.env", __dir__)
  Dotenv.load(env_file) if File.exist?(env_file)
rescue LoadError
  warn "dotenv gem not available; continuing without loading .env"
end

require_relative "../config/environment"

puts "=" * 60
puts "SAFE DATA DELETION SCRIPT"
puts "=" * 60
puts ""

# Show current counts
puts "Current data counts:"
puts "  Users: #{User.count}"
puts "  Guilds: #{Guild.count}"
puts "  Events: #{Event.count}"
puts "  GuildMembers: #{GuildMember.count}"
puts "  Subscriptions: #{Subscription.count}"
  puts "  GuildApplications: #{GuildApplication.count}"
  puts "  GuildInvites: #{GuildInvite.count}" if defined?(GuildInvite)
puts "  DiscordConnections: #{DiscordConnection.count}"
puts "  UserDiscordConnections: #{UserDiscordConnection.count}"
puts "  GuildDiscordSettings: #{GuildDiscordSetting.count}"
puts "  DiscordEvents: #{DiscordEvent.count}"
puts "  EventParticipations: #{EventParticipation.count}"
  puts "  DiscordEventParticipations: #{DiscordEventParticipation.count}"
  puts "  DiscordRoleSyncs: #{DiscordRoleSync.count}" if defined?(DiscordRoleSync)
  puts "  GearSnapshots: #{GearSnapshot.count}" if defined?(GearSnapshot)
  puts "  GearUploadRequests: #{GearUploadRequest.count}" if defined?(GearUploadRequest)
  puts "  PricingPlans: #{PricingPlan.count} (will be preserved)"
  puts ""

# Confirm deletion (skip if running non-interactively)
if $stdin.tty?
  print "Are you sure you want to delete ALL user data? (yes/no): "
  confirmation = $stdin.gets&.chomp&.downcase

  unless confirmation == "yes"
    puts "Deletion cancelled."
    exit 0
  end
else
  puts "Running non-interactively - proceeding with deletion..."
end

puts ""
puts "Starting deletion process..."
puts ""

# Use transaction for safety
ActiveRecord::Base.transaction do
  deleted_counts = {}

  # Delete in order to respect foreign key constraints

  # 1. Delete Discord-related data first
  puts "Deleting Discord role syncs..."
  deleted_counts[:discord_role_syncs] = DiscordRoleSync.delete_all if defined?(DiscordRoleSync)

  puts "Deleting Discord event participations..."
  deleted_counts[:discord_event_participations] = DiscordEventParticipation.delete_all

  puts "Deleting Discord event signups..."
  deleted_counts[:discord_event_signups] = DiscordEventSignup.delete_all

  puts "Deleting Discord events..."
  deleted_counts[:discord_events] = DiscordEvent.delete_all

  puts "Deleting guild Discord settings..."
  deleted_counts[:guild_discord_settings] = GuildDiscordSetting.delete_all

  puts "Deleting Discord connections..."
  deleted_counts[:discord_connections] = DiscordConnection.delete_all

  puts "Deleting user Discord connections..."
  deleted_counts[:user_discord_connections] = UserDiscordConnection.delete_all

  # 2. Delete event-related data
  puts "Deleting event participations..."
  deleted_counts[:event_participations] = EventParticipation.delete_all

  puts "Deleting events..."
  deleted_counts[:events] = Event.delete_all

  # 3. Delete gear-related data
  puts "Deleting gear upload requests..."
  deleted_counts[:gear_upload_requests] = GearUploadRequest.delete_all if defined?(GearUploadRequest)

  puts "Deleting gear snapshots..."
  deleted_counts[:gear_snapshots] = GearSnapshot.delete_all if defined?(GearSnapshot)

  # 4. Delete guild-related data
  puts "Deleting guild applications..."
  deleted_counts[:guild_applications] = GuildApplication.delete_all

  puts "Deleting guild invites..."
  deleted_counts[:guild_invites] = GuildInvite.delete_all if defined?(GuildInvite)

  puts "Deleting guild members..."
  deleted_counts[:guild_members] = GuildMember.delete_all

  puts "Deleting guild games..."
  deleted_counts[:guild_games] = GuildGame.delete_all if defined?(GuildGame)

  puts "Deleting guilds..."
  deleted_counts[:guilds] = Guild.delete_all

  # 5. Delete user-related data
  puts "Deleting subscriptions..."
  deleted_counts[:subscriptions] = Subscription.delete_all

  # 6. Delete users (this will cascade to dependent records via associations)
  puts "Deleting users..."
  deleted_counts[:users] = User.delete_all

  # 7. Clean up Active Storage attachments (includes gear screenshots)
  puts "Cleaning up Active Storage attachments..."
  deleted_counts[:active_storage_attachments] = ActiveStorage::Attachment.delete_all
  deleted_counts[:active_storage_blobs] = ActiveStorage::Blob.where.not(id: ActiveStorage::Attachment.select(:blob_id).distinct).delete_all

  puts ""
  puts "=" * 60
  puts "DELETION COMPLETE"
  puts "=" * 60
  puts ""
  puts "Records deleted:"
  deleted_counts.each do |model, count|
    puts "  #{model.to_s.humanize}: #{count}"
  end
  puts ""
  puts "Pricing plans preserved: #{PricingPlan.count}"
  puts ""
  puts "Database is now clean and ready for testing."
  puts ""
end

puts "Script completed successfully."
