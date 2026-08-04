#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to set up test data for integration tests
# Usage: rails runner script/setup_test_data.rb
#        or: RAILS_ENV=test rails runner script/setup_test_data.rb

puts "Setting up test data for integration tests..."
puts "=" * 80

def confirm_integration_user!(user)
  return unless user.respond_to?(:confirmed?) && !user.confirmed?

  user.update!(
    confirmed_at: Time.current,
    confirmation_token: nil,
    confirmation_sent_at: nil,
    unconfirmed_email: nil
  )
end

# Create Free plan
free_plan = PricingPlan.find_or_create_by!(name: "Free") do |plan|
  plan.price = 0
  plan.price_display = "$0"
  plan.period = "forever"
  plan.max_guilds = 1
  plan.max_members_per_guild = 10
  plan.active = true
  plan.display_order = 1
end

if free_plan.persisted? && free_plan.previously_new_record?
  puts "✓ Created Free plan"
else
  puts "✓ Free plan already exists"
end

# Create first test user WITH subscription (with Discord auth method to bypass MFA)
# Using unique email/username to avoid conflicts with spec factories
test_user = User.find_or_create_by!(email: "test_data@example.com") do |user|
  user.username = "testdatauser"
  user.password = "password123"
  user.password_confirmation = "password123"
  user.auth_method = "discord"  # Bypasses MFA for faster tests
end

if test_user.persisted?
  updates = {}
  updates[:auth_method] = "discord" if test_user.auth_method != "discord"
  # Always ensure the expected password is set — find_or_create_by! only sets it on creation
  unless test_user.valid_password?("password123")
    updates[:password] = "password123"
    updates[:password_confirmation] = "password123"
  end
  unless updates.empty?
    test_user.update!(updates)
    puts "✓ Updated test user attributes: #{updates.keys.join(', ')}"
  end
  confirm_integration_user!(test_user)

  if test_user.previously_new_record?
    puts "✓ Created test user: test_data@example.com"
  else
    puts "✓ Test user already exists: test_data@example.com"
  end
else
  puts "✗ Failed to create test user"
  puts "  Errors: #{test_user.errors.full_messages.join(', ')}"
end

# Ensure first test user has a Free plan subscription for integration tests
# Note: The User model's after_create callback (ensure_free_plan_subscription) will create
# a subscription automatically when the user is created. For integration tests, we want
# to keep this subscription so the test user can fully use the application.
if test_user.persisted?
  test_user.reload
  
  # Ensure Free plan subscription exists for integration tests
  unless test_user.subscriptions.current.exists?
    test_user.ensure_free_plan_subscription
    puts "✓ Created Free plan subscription for test user"
  else
    # Update existing subscription to Free plan if needed
    current_sub = test_user.subscriptions.current.first
    if current_sub.pricing_plan != free_plan
      current_sub.update!(pricing_plan: free_plan, status: :active)
      puts "✓ Updated test user subscription to Free plan"
    else
      puts "✓ Test user already has Free plan subscription"
    end
  end
end

# Create second test user WITHOUT subscription (for tests that need to create subscriptions)
# This user will have no subscription so tests can create specific subscription scenarios
test_user_no_sub = User.find_by(email: "test_data_no_sub@example.com")

if test_user_no_sub.nil?
  # Create new user with skip flag to prevent callback from creating subscription
  test_user_no_sub = User.new(
    email: "test_data_no_sub@example.com",
    username: "testdatausernosub",
    password: "password123",
    password_confirmation: "password123",
    auth_method: "discord"
  )
  test_user_no_sub.skip_free_plan_subscription = true  # Prevent callback from creating subscription
  test_user_no_sub.save!
  puts "✓ Created test user (no subscription): test_data_no_sub@example.com"
else
  puts "✓ Test user (no subscription) already exists: test_data_no_sub@example.com"
end

if test_user_no_sub.persisted?
  no_sub_updates = {}
  no_sub_updates[:auth_method] = "discord" if test_user_no_sub.auth_method != "discord"
  unless test_user_no_sub.valid_password?("password123")
    no_sub_updates[:password] = "password123"
    no_sub_updates[:password_confirmation] = "password123"
  end
  unless no_sub_updates.empty?
    test_user_no_sub.update!(no_sub_updates)
    puts "✓ Updated test user (no sub) attributes: #{no_sub_updates.keys.join(', ')}"
  end
  confirm_integration_user!(test_user_no_sub)
  
  # Ensure this user has NO subscriptions (delete any that might exist)
  if test_user_no_sub.subscriptions.any?
    test_user_no_sub.subscriptions.destroy_all
    puts "✓ Removed subscriptions from test user (no sub)"
  else
    puts "✓ Test user (no subscription) already exists: test_data_no_sub@example.com"
  end
else
  puts "✗ Failed to create test user (no subscription)"
  puts "  Errors: #{test_user_no_sub.errors.full_messages.join(', ')}"
end

# Create a test game (needed for guild creation tests)
# Use a unique slug/name to avoid conflicts with spec factories
test_game = Game.find_or_create_by!(slug: "integration-test-game") do |game|
  game.name = "Integration Test Game"
  game.description = "Default test game for integration tests"
  game.active = true
  game.ocr_config = {}
end

if test_game.persisted?
  if test_game.previously_new_record?
    puts "✓ Created test game: Integration Test Game"
  else
    puts "✓ Test game already exists: Integration Test Game"
  end
else
  puts "✗ Failed to create test game"
  puts "  Errors: #{test_game.errors.full_messages.join(', ')}"
end

puts "=" * 80
puts "Test data setup complete!"
puts ""
puts "Test user credentials (WITH subscription):"
puts "  Email: test_data@example.com"
puts "  Username: testdatauser"
puts "  Password: password123"
puts "  Auth Method: discord (bypasses MFA)"
puts "  Subscription: Free plan (active)"
puts ""
puts "Test user credentials (WITHOUT subscription):"
puts "  Email: test_data_no_sub@example.com"
puts "  Username: testdatausernosub"
puts "  Password: password123"
puts "  Auth Method: discord (bypasses MFA)"
puts "  Subscription: None (tests can create as needed)"
puts ""

# Create third test user WITH subscription AND MFA enabled (for manual MFA testing)
# Use TEST_MFA_SECRET environment variable or default to match test expectations
test_mfa_secret = ENV['TEST_MFA_SECRET'] || "JBSWY3DPEHPK3PXP"

test_user_mfa = User.find_by(email: "test_data_mfa@example.com")

if test_user_mfa.nil?
  # Create new user with MFA enabled
  test_user_mfa = User.new(
    email: "test_data_mfa@example.com",
    username: "testdatausermfa",
    password: "password123",
    password_confirmation: "password123",
    auth_method: "mfa"
  )
  test_user_mfa.skip_free_plan_subscription = true  # Prevent callback from creating subscription
  # Set OTP secret before saving so the after_create callback skips random generation
  test_user_mfa.otp_secret = test_mfa_secret
  test_user_mfa.save!
  
  # Ensure OTP secret is set correctly (in case callback overwrote it)
  if test_user_mfa.otp_secret != test_mfa_secret
    test_user_mfa.update!(otp_secret: test_mfa_secret)
  end
  
  # Enable MFA after creation
  test_user_mfa.update!(mfa_enabled: true, mfa_verified: true)
  
  # Create Free plan subscription
  unless test_user_mfa.subscriptions.current.exists?
    test_user_mfa.ensure_free_plan_subscription
    puts "✓ Created Free plan subscription for test user (MFA)"
  end
  
  puts "✓ Created test user (MFA): test_data_mfa@example.com"
  puts "  ✓ OTP secret set to: #{test_mfa_secret}"
else
  puts "✓ Test user (MFA) already exists: test_data_mfa@example.com"
  unless test_user_mfa.valid_password?("password123")
    test_user_mfa.update!(password: "password123", password_confirmation: "password123")
    puts "✓ Reset password for test user (MFA)"
  end
end

if test_user_mfa.persisted?
  confirm_integration_user!(test_user_mfa)

  # Ensure OTP secret matches test expectations (for both new and existing users)
  if test_user_mfa.otp_secret != test_mfa_secret
    test_user_mfa.update!(otp_secret: test_mfa_secret)
    puts "✓ Updated OTP secret to match test expectations: #{test_mfa_secret}"
  else
    puts "  ✓ OTP secret matches test expectations: #{test_mfa_secret}"
  end
  
  # Ensure MFA is enabled
  if !test_user_mfa.mfa_enabled?
    test_user_mfa.update!(mfa_enabled: true, mfa_verified: true)
    puts "✓ Enabled MFA for test user (MFA)"
  else
    puts "  ✓ Test user (MFA) already has MFA enabled"
  end
  
  # Ensure Free plan subscription exists
  unless test_user_mfa.subscriptions.current.exists?
    test_user_mfa.ensure_free_plan_subscription
    puts "✓ Created Free plan subscription for test user (MFA)"
  else
    puts "  ✓ Test user (MFA) already has Free plan subscription"
  end
end

puts ""
puts "Test user credentials (WITH subscription AND MFA):"
puts "  Email: test_data_mfa@example.com"
puts "  Username: testdatausermfa"
puts "  Password: password123"
puts "  Auth Method: mfa (requires MFA verification)"
puts "  Subscription: Free plan (active)"
puts "  MFA Enabled: Yes"
puts "  OTP Secret: #{test_user_mfa.otp_secret}" if test_user_mfa.persisted?
puts "  Note: OTP secret matches TEST_MFA_SECRET env var or default (JBSWY3DPEHPK3PXP)"
puts ""
puts "You can now run integration tests."
