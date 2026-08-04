# Database wipe rake task - clears all user accounts and related records
# ⚠️  WARNING: THIS TASK PERMANENTLY DELETES ALL DATA ⚠️
# 
# SECURITY: This task is ONLY for development/testing environments.
# It will REFUSE to run in production or staging to prevent data loss.
#
# Run with: bin/rails wipe_database
#
# This task should NOT be in production. Consider removing entirely.

namespace :db do
  desc "⚠️  DANGER: Wipe all user data (development/test only)"
  task wipe: :environment do
    # CRITICAL SAFETY CHECK: Prevent execution in production/staging
    if Rails.env.production? || Rails.env.staging?
      puts "=" * 80
      puts "🚨 SECURITY BLOCKED 🚨"
      puts "=" * 80
      puts "This task is BLOCKED from running in #{Rails.env} environment."
      puts "It would permanently delete ALL user data, guilds, events, and subscriptions."
      puts ""
      puts "If you need to reset data in #{Rails.env}, use database migrations or"
      puts "proper data management tools instead."
      puts "=" * 80
      exit 1
    end

    # Additional confirmation in development
    unless Rails.env.test?
      puts "=" * 80
      puts "⚠️  DANGER: DATABASE WIPE TASK ⚠️"
      puts "=" * 80
      puts "This will PERMANENTLY DELETE:"
      puts "  - All user accounts"
      puts "  - All guilds"
      puts "  - All events"
      puts "  - All subscriptions"
      puts "  - All Discord connections"
      puts "  - All related data"
      puts ""
      puts "This action CANNOT be undone!"
      puts ""
      print "Type 'DELETE ALL DATA' to confirm: "
      confirmation = STDIN.gets.chomp
      
      unless confirmation == "DELETE ALL DATA"
        puts "❌ Confirmation failed. Task aborted."
        exit 1
      end
      puts ""
    end

    puts 'Clearing all user accounts and related records...'

    # Clear Active Storage attachments first
    ActiveStorage::Attachment.all.each(&:purge)
    puts '✓ Cleared Active Storage attachments'

    # Delete all users (this will cascade delete related records due to dependent: :destroy)
    user_count = User.count
    User.destroy_all
    puts "✓ Deleted #{user_count} users"

    # Clear any remaining orphaned records (in case of any that don't cascade)
    Guild.destroy_all
    puts '✓ Cleared any remaining guilds'

    Event.destroy_all
    puts '✓ Cleared any remaining events'

    DiscordEvent.destroy_all
    puts '✓ Cleared any remaining Discord events'

    GuildApplication.destroy_all
    puts '✓ Cleared any remaining guild applications'

    Subscription.destroy_all
    puts '✓ Cleared any remaining subscriptions'

    DiscordConnection.destroy_all
    puts '✓ Cleared any remaining Discord connections'

    UserDiscordConnection.destroy_all
    puts '✓ Cleared any remaining User Discord connections'

    # Clear Active Storage blobs that are no longer referenced
    ActiveStorage::Blob.unattached.find_each(&:purge)
    puts '✓ Cleared unattached Active Storage blobs'

    puts ''
    puts '✅ All user accounts and related records have been cleared!'
    puts 'ℹ️  Pricing plans have been preserved.'
  end
end
