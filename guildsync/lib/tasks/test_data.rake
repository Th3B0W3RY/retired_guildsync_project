# frozen_string_literal: true

namespace :test_data do
  desc "Set up test data for integration tests (test user, free plan, etc.)"
  desc "Note: This data is for integration tests, not spec tests. Spec tests use transactional fixtures and create their own test data."
  task setup: :environment do
    # Runs against whichever database RAILS_ENV points to.
    # Development server → RAILS_ENV=development (default for `rails server`)
    # CI / isolated runs  → RAILS_ENV=test
    # The setup script is idempotent in either environment.
    puts "Running test_data:setup against RAILS_ENV=#{Rails.env}"

    load File.expand_path("../../script/setup_test_data.rb", __dir__)
  end

  desc "Verify test data is set up correctly"
  task verify: :environment do
    puts "Verifying test data setup..."
    puts "=" * 80

    errors = []

    # Check Free plan
    free_plan = PricingPlan.find_by(name: "Free")
    if free_plan.nil?
      errors << "Free plan not found"
    elsif !free_plan.active?
      errors << "Free plan exists but is not active"
    else
      puts "✓ Free plan exists and is active"
    end

    # Check first test user (WITH subscription)
    test_user = User.find_by(email: "test_data@example.com")
    if test_user.nil?
      errors << "Test user (test_data@example.com) not found"
    else
      puts "✓ Test user exists: test_data@example.com"
      
      # Check auth_method
      if test_user.auth_method != "discord"
        errors << "Test user auth_method is '#{test_user.auth_method}' (should be 'discord')"
      else
        puts "  ✓ Auth method is 'discord' (MFA bypass enabled)"
      end

      # Check password
      unless test_user.valid_password?("password123")
        errors << "Test user password is not 'password123'"
      else
        puts "  ✓ Password is correct"
      end

      # Check subscription
      if test_user.subscriptions.current.exists?
        current_sub = test_user.subscriptions.current.first
        if current_sub.pricing_plan.name == "Free"
          puts "  ✓ Has active Free plan subscription"
        else
          errors << "Test user subscription is for plan '#{current_sub.pricing_plan.name}' (should be 'Free')"
        end
      else
        errors << "Test user has no current subscription"
      end
    end

    # Check second test user (WITHOUT subscription)
    test_user_no_sub = User.find_by(email: "test_data_no_sub@example.com")
    if test_user_no_sub.nil?
      errors << "Test user (no subscription) (test_data_no_sub@example.com) not found"
    else
      puts "✓ Test user (no subscription) exists: test_data_no_sub@example.com"
      
      # Check auth_method
      if test_user_no_sub.auth_method != "discord"
        errors << "Test user (no sub) auth_method is '#{test_user_no_sub.auth_method}' (should be 'discord')"
      else
        puts "  ✓ Auth method is 'discord' (MFA bypass enabled)"
      end

      # Check password
      unless test_user_no_sub.valid_password?("password123")
        errors << "Test user (no sub) password is not 'password123'"
      else
        puts "  ✓ Password is correct"
      end

      # Check that this user has NO subscriptions
      if test_user_no_sub.subscriptions.any?
        errors << "Test user (no sub) has subscriptions (should have none)"
      else
        puts "  ✓ Has no subscriptions (as expected)"
      end
    end

    # Check third test user (WITH subscription AND MFA)
    test_user_mfa = User.find_by(email: "test_data_mfa@example.com")
    if test_user_mfa.nil?
      errors << "Test user (MFA) (test_data_mfa@example.com) not found"
    else
      puts "✓ Test user (MFA) exists: test_data_mfa@example.com"
      
      # Check auth_method
      if test_user_mfa.auth_method != "mfa"
        errors << "Test user (MFA) auth_method is '#{test_user_mfa.auth_method}' (should be 'mfa')"
      else
        puts "  ✓ Auth method is 'mfa' (requires MFA verification)"
      end
      
      # Check password
      unless test_user_mfa.valid_password?("password123")
        errors << "Test user (MFA) password is not 'password123'"
      else
        puts "  ✓ Password is correct"
      end
      
      # Check MFA is enabled
      unless test_user_mfa.mfa_enabled?
        errors << "Test user (MFA) does not have MFA enabled"
      else
        puts "  ✓ MFA is enabled"
      end
      
      # Check OTP secret exists and matches test expectations
      expected_secret = ENV['TEST_MFA_SECRET'] || "JBSWY3DPEHPK3PXP"
      if test_user_mfa.otp_secret.blank?
        errors << "Test user (MFA) does not have OTP secret"
      elsif test_user_mfa.otp_secret != expected_secret
        errors << "Test user (MFA) OTP secret does not match expected value (expected: #{expected_secret}, got: #{test_user_mfa.otp_secret})"
      else
        puts "  ✓ OTP secret is present and matches test expectations"
      end
      
      # Check subscription
      if test_user_mfa.subscriptions.current.exists?
        current_sub = test_user_mfa.subscriptions.current.first
        if current_sub.pricing_plan.name == "Free"
          puts "  ✓ Has active Free plan subscription"
        else
          errors << "Test user (MFA) subscription is for plan '#{current_sub.pricing_plan.name}' (should be 'Free')"
        end
      else
        errors << "Test user (MFA) has no current subscription"
      end
    end
    
    # Check test game
    # Note: Uses unique slug/name to avoid conflicts with spec factories
    test_game = Game.find_by(slug: "integration-test-game")
    if test_game.nil?
      errors << "Test game not found"
    elsif !test_game.active?
      errors << "Test game exists but is not active"
    else
      puts "✓ Test game exists and is active"
    end

    puts "=" * 80

    if errors.any?
      puts "✗ Verification failed with #{errors.length} error(s):"
      errors.each { |error| puts "  - #{error}" }
      puts ""
      puts "Run 'rails test_data:setup' to fix these issues."
      exit 1
    else
      puts "✓ All test data is set up correctly!"
      exit 0
    end
  end
end

# Helper method to set up test data after schema is loaded
def setup_test_data_after_schema_load
  # Ensure test environment - db:test:load_schema is always for test database
  original_env = ENV["RAILS_ENV"]
  ENV["RAILS_ENV"] = "test"
  
  begin
    if defined?(Rails) && Rails.env != "test"
      Rails.env = "test"
    end
    
    # The setup script already prints headers, so we just invoke it
    Rake::Task["test_data:setup"].invoke
  ensure
    ENV["RAILS_ENV"] = original_env if original_env
  end
end

# Automatically set up test data after test database schema is loaded
# This ensures test data is ready whenever the test database is prepared
# Hooks into db:test:load_schema which runs after db:test:purge and loads the schema
# Note: db:test:prepare calls db:test:load_schema, so enhancing this task covers both cases
if Rake::Task.task_defined?("db:test:load_schema")
  Rake::Task["db:test:load_schema"].enhance do
    setup_test_data_after_schema_load
  end
end
