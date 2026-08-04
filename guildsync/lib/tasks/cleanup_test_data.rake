namespace :test_data do
  desc "Delete all test accounts and related data for fresh testing"
  task cleanup: :environment do
    puts "=" * 60
    puts "Cleaning up all test data..."
    puts "=" * 60

    # Start transaction for safety
    ActiveRecord::Base.transaction do
      # Delete in order to respect foreign key constraints
      
      # 1. Discord Event Signups (references discord_events and discord_users)
      signup_count = DiscordEventSignup.count
      DiscordEventSignup.delete_all
      puts "  ✓ Deleted #{signup_count} Discord Event Signups"

      # 2. Discord Events (references guilds and discord_connections)
      event_count = DiscordEvent.count
      DiscordEvent.delete_all
      puts "  ✓ Deleted #{event_count} Discord Events"

      # 3. User Discord Connections (references users)
      connection_count = UserDiscordConnection.count
      UserDiscordConnection.delete_all
      puts "  ✓ Deleted #{connection_count} User Discord Connections"

      # 4. Guild Discord Settings (references guilds)
      guild_setting_count = GuildDiscordSetting.count
      GuildDiscordSetting.delete_all
      puts "  ✓ Deleted #{guild_setting_count} Guild Discord Settings"

      # 5. Discord Connections (references guilds and users)
      discord_connection_count = DiscordConnection.count
      DiscordConnection.delete_all
      puts "  ✓ Deleted #{discord_connection_count} Discord Connections"

      # 6. Guild Members (references users and guilds)
      guild_member_count = GuildMember.count
      GuildMember.delete_all
      puts "  ✓ Deleted #{guild_member_count} Guild Members"

      # 7. Guild Applications (references users and guilds)
      guild_application_count = GuildApplication.count
      GuildApplication.delete_all
      puts "  ✓ Deleted #{guild_application_count} Guild Applications"

      # 8. Event Participations (references users and events)
      event_participation_count = EventParticipation.count
      EventParticipation.delete_all
      puts "  ✓ Deleted #{event_participation_count} Event Participations"

      # 9. Discord Event Participations (references events)
      discord_event_participation_count = DiscordEventParticipation.count
      DiscordEventParticipation.delete_all
      puts "  ✓ Deleted #{discord_event_participation_count} Discord Event Participations"

      # 10. Events (references users as creator)
      event_count = Event.count
      Event.delete_all
      puts "  ✓ Deleted #{event_count} Events"

      # 11. Subscriptions (references users)
      subscription_count = Subscription.count
      Subscription.delete_all
      puts "  ✓ Deleted #{subscription_count} Subscriptions"

      # 12. Guilds (references users as owner)
      guild_count = Guild.count
      Guild.delete_all
      puts "  ✓ Deleted #{guild_count} Guilds"

      # 13. Users (delete all users - must be last due to foreign keys)
      user_count = User.count
      User.delete_all
      puts "  ✓ Deleted #{user_count} Users"

      # 9. Any other related records
      # Add more if needed based on your schema

      puts "=" * 60
      puts "Cleanup complete! All test data has been deleted."
      puts "=" * 60
    end
  end
end

