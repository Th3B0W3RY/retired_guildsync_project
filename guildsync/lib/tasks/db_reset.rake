# frozen_string_literal: true

namespace :db do
  desc "Reset database and reseed (WARNING: Deletes all data!)"
  task reset_with_seed: :environment do
    puts "⚠️  WARNING: This will delete ALL data from the database!"
    puts "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5
    
    puts "Dropping all tables..."
    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.drop_table(table) if table != 'schema_migrations'
    end
    
    puts "Running migrations..."
    Rake::Task['db:migrate'].invoke
    
    puts "Seeding database..."
    Rake::Task['db:seed'].invoke
    
    puts "✅ Database reset complete!"
  end
  
  desc "Delete all users and their associated data"
  task purge_users: :environment do
    puts "⚠️  WARNING: This will delete ALL users and their associated data!"
    puts "This includes: subscriptions, guilds, events, participations, etc."
    puts "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5
    
    user_count = User.count
    puts "Deleting #{user_count} users..."
    
    User.destroy_all
    
    puts "✅ Deleted #{user_count} users and all associated data!"
    puts "Remaining records:"
    puts "  Users: #{User.count}"
    puts "  Guilds: #{Guild.count}"
    puts "  Events: #{Event.count}"
    puts "  Subscriptions: #{Subscription.count}"
  end
end

