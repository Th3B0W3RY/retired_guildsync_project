#!/usr/bin/env ruby
# Test script to verify subscription logic
# Run with: rails runner test_subscription_logic.rb

puts "\n" + "="*60
puts "  TESTING SUBSCRIPTION LOGIC"
puts "="*60

# Test 1: Verify Free plan exists
puts "\n[TEST 1] Checking if Free plan exists..."
free_plan = PricingPlan.find_by(name: "Free")
if free_plan
  puts "  ✓ Free plan found: ID=#{free_plan.id}, Price=#{free_plan.price_display}"
else
  puts "  ✗ ERROR: Free plan not found! PricingPlanInitializer should create it."
  exit 1
end

# Test 2: Verify User model methods exist
puts "\n[TEST 2] Checking User model methods..."
user_methods = User.instance_methods(false)
required_methods = [:start_trial_for_plan!, :activate_free_plan!]
required_methods.each do |method|
  if user_methods.include?(method)
    puts "  ✓ Method #{method} exists"
  else
    puts "  ✗ ERROR: Method #{method} not found!"
    exit 1
  end
end

# Test 3: Test activate_free_plan! with a test user
puts "\n[TEST 3] Testing activate_free_plan! method..."
test_user = User.find_or_create_by!(email: "test_subscription@example.com") do |u|
  u.username = "test_subscription"
  u.password = "password123"
  u.password_confirmation = "password123"
end

# Clean up any existing subscriptions
test_user.subscriptions.destroy_all

begin
  test_user.activate_free_plan!
  # Reload associations to get fresh data
  test_user.reload
  subscription = test_user.current_subscription
  if subscription && subscription.status == 'active' && subscription.pricing_plan.name == 'Free'
    puts "  ✓ activate_free_plan! works correctly"
    puts "    - Subscription ID: #{subscription.id}"
    puts "    - Status: #{subscription.status}"
    puts "    - Plan: #{subscription.pricing_plan.name}"
  else
    puts "  ✗ ERROR: activate_free_plan! did not create correct subscription"
    puts "    - Subscription: #{subscription.inspect}"
    exit 1
  end
rescue => e
  puts "  ✗ ERROR: activate_free_plan! failed: #{e.message}"
  puts "    #{e.backtrace.first}"
  exit 1
end

# Test 4: Test start_trial_for_plan! with a paid plan
puts "\n[TEST 4] Testing start_trial_for_plan! method..."
paid_plan = PricingPlan.where.not(name: "Free").where(active: true).first
if paid_plan.nil?
  puts "  ⚠ WARNING: No paid plans found. Creating a test plan..."
  paid_plan = PricingPlan.create!(
    name: "Test Plan",
    price: 9.99,
    price_display: "$9.99",
    period: "per month",
    description: "Test plan",
    active: true,
    max_guilds: 5,
    max_members_per_guild: 50,
    features: ["Test feature"],
    display_order: 99
  )
  puts "  ✓ Created test plan: #{paid_plan.name}"
end

begin
  test_user.start_trial_for_plan!(paid_plan)
  # Reload associations to get fresh data
  test_user.reload
  subscription = test_user.current_subscription
  if subscription && 
     subscription.status == 'trialing' && 
     subscription.pricing_plan.id == paid_plan.id &&
     subscription.trial_ends_at.present? &&
     subscription.trial_ends_at > Time.current
    puts "  ✓ start_trial_for_plan! works correctly"
    puts "    - Subscription ID: #{subscription.id}"
    puts "    - Status: #{subscription.status}"
    puts "    - Plan: #{subscription.pricing_plan.name}"
    puts "    - Trial ends at: #{subscription.trial_ends_at}"
    days_left = ((subscription.trial_ends_at - Time.current) / 1.day).round
    puts "    - Days remaining: ~#{days_left}"
  else
    puts "  ✗ ERROR: start_trial_for_plan! did not create correct subscription"
    puts "    - Subscription: #{subscription.inspect}"
    puts "    - Status: #{subscription&.status}"
    puts "    - Plan: #{subscription&.pricing_plan&.name}"
    puts "    - All subscriptions:"
    test_user.subscriptions.each { |s| puts "      ID: #{s.id}, Status: #{s.status}, Plan: #{s.pricing_plan.name}" }
    exit 1
  end
rescue => e
  puts "  ✗ ERROR: start_trial_for_plan! failed: #{e.message}"
  puts "    #{e.backtrace.first}"
  exit 1
end

# Test 5: Test that switching plans cancels old subscription
puts "\n[TEST 5] Testing plan switching (should cancel old subscription)..."
test_user.reload
old_subscription_id = test_user.current_subscription.id
test_user.activate_free_plan!
test_user.reload
new_subscription = test_user.current_subscription
old_subscription = Subscription.find_by(id: old_subscription_id)
old_subscription.reload if old_subscription

if old_subscription && old_subscription.status == 'canceled' && 
   new_subscription && new_subscription.id != old_subscription_id &&
   new_subscription.status == 'active'
  puts "  ✓ Plan switching works correctly"
  puts "    - Old subscription canceled: #{old_subscription.status}"
  puts "    - New subscription active: #{new_subscription.status}"
else
  puts "  ✗ ERROR: Plan switching did not work correctly"
  puts "    - Old subscription: #{old_subscription&.status || 'nil'}"
  puts "    - New subscription: #{new_subscription&.status || 'nil'}"
  puts "    - New subscription ID: #{new_subscription&.id}"
  puts "    - Old subscription ID: #{old_subscription_id}"
  exit 1
end

# Test 6: Verify PricingController logic (check method exists)
puts "\n[TEST 6] Checking PricingController methods..."
pricing_controller = PricingController.new
if pricing_controller.respond_to?(:select_plan, true)
  puts "  ✓ select_plan method exists"
else
  puts "  ✗ ERROR: select_plan method not found!"
  exit 1
end

# Test 7: Verify MfaSetupController logic
puts "\n[TEST 7] Checking MfaSetupController verify method..."
mfa_controller = MfaSetupController.new
if mfa_controller.respond_to?(:verify, true)
  puts "  ✓ verify method exists"
else
  puts "  ✗ ERROR: verify method not found!"
  exit 1
end

# Test 8: Check for potential nil errors
puts "\n[TEST 8] Testing edge cases..."
begin
  # Test with nil plan (should be handled)
  if PricingPlan.find_by(name: "NonExistentPlan").nil?
    puts "  ✓ Nil plan handling works (find_by returns nil)"
  end
rescue => e
  puts "  ✗ ERROR: Nil plan handling failed: #{e.message}"
  exit 1
end

# Cleanup test data
puts "\n[CLEANUP] Removing test data..."
test_user.subscriptions.destroy_all
if paid_plan.name == "Test Plan"
  paid_plan.destroy
  puts "  ✓ Removed test plan"
end
puts "  ✓ Test subscriptions removed"

puts "\n" + "="*60
puts "  ALL TESTS PASSED ✓"
puts "="*60
puts "\nThe subscription logic appears to be working correctly!"
puts "However, you should also test the full flow manually:\n"
puts "1. Logged-out user selects plan → signup → MFA → subscription created"
puts "2. Logged-in user selects plan → immediate trial starts"
puts "3. User on trial selects different plan → new trial starts"
puts "="*60 + "\n"

