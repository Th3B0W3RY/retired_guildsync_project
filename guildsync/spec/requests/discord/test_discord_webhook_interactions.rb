#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone test script for Discord webhook interactions
# Run with: ruby test_discord_webhook_interactions.rb

require_relative 'config/environment'

puts "=" * 80
puts "DISCORD WEBHOOK INTERACTION TEST - 10 ITERATIONS"
puts "=" * 80
puts

# Test data setup
user = User.first || User.create!(
  email: "test@example.com",
  password: "password123",
  username: "testuser"
)

pricing_plan = PricingPlan.find_or_create_by!(name: "Free") do |plan|
  plan.max_guilds = 10
  plan.price = 0
  plan.active = true
end

subscription = Subscription.find_or_create_by!(user: user) do |sub|
  sub.pricing_plan = pricing_plan
  sub.status = "active"
  sub.starts_at = Time.current
  sub.ends_at = 1.year.from_now
end

guild = Guild.find_or_create_by!(owner: user) do |g|
  g.name = "Test Guild"
  g.description = "Test guild for webhook testing"
end

discord_connection = DiscordConnection.find_or_create_by!(guild: guild, user: user) do |dc|
  dc.discord_user_id = "123456789012345678"
  dc.discord_username = "TestUser#1234"
  dc.access_token = "fake_access_token"
  dc.refresh_token = "fake_refresh_token"
  dc.expires_at = 1.hour.from_now
  dc.scopes = "identify guilds"
end

discord_event = DiscordEvent.find_or_create_by!(discord_event_id: "test_event_123") do |de|
  de.guild = guild
  de.discord_connection = discord_connection
  de.discord_message_id = "test_message_123"
  de.channel_id = "test_channel_123"
  de.title = "Test Event"
  de.description = "This is a test event"
  de.scheduled_at = 1.day.from_now
  de.event_type = "pvp"
end

# Test parameters
fake_discord_user_id = "123456789012345678"
fake_interaction_token = SecureRandom.hex(32)
fake_interaction_id = SecureRandom.hex(16)

# Mock signature verification
class DiscordWebhooksController
  alias_method :original_verify_discord_signature, :verify_discord_signature

  def verify_discord_signature(signature, timestamp, body)
    # Skip verification for testing
    true
  end
end

# Mock DiscordService
class DiscordService
  alias_method :original_update_message, :update_message

  def update_message(*args)
    # Mock successful update
    true
  end
end

# Helper to create interaction request
def create_interaction_request(interaction_data)
  body = interaction_data.to_json
  timestamp = Time.now.to_i.to_s
  signature = "0" * 128 # Fake signature

  {
    body: body,
    headers: {
      "X-Signature-Ed25519" => signature,
      "X-Signature-Timestamp" => timestamp,
      "Content-Type" => "application/json"
    }
  }
end

# Helper to create button interaction
def create_button_interaction(event_id, role, channel_id, user_id: "123456789012345678", token: nil, interaction_id: nil)
  token ||= SecureRandom.hex(32)
  interaction_id ||= SecureRandom.hex(16)

  {
    "type" => 3, # MESSAGE_COMPONENT
    "token" => token,
    "id" => interaction_id,
    "data" => {
      "custom_id" => "event_signup_#{event_id}_#{role}",
      "component_type" => 2
    },
    "member" => {
      "user" => {
        "id" => user_id,
        "username" => "TestUser",
        "discriminator" => "1234",
        "global_name" => nil
      }
    },
    "guild_id" => "987654321098765432",
    "channel_id" => channel_id
  }
end

# Test results
results = {
  total: 0,
  passed: 0,
  failed: 0,
  errors: [],
  response_times: []
}

puts "Starting 10 test iterations on existing event..."
puts
puts "Testing rapid button clicks on the same event to verify status cycling..."
puts

# Clear any existing signups for clean test
discord_event.discord_event_signups.where(discord_user_id: fake_discord_user_id, role: "dps").destroy_all

10.times do |iteration|
  iteration_num = iteration + 1
  puts "Iteration #{iteration_num}/10..."

  begin
    # CRITICAL: Each Discord interaction MUST have a unique token and ID
    # Discord rejects duplicate interaction tokens
    unique_token = SecureRandom.hex(32)
    unique_id = SecureRandom.hex(16)

    # Create interaction with unique token
    interaction = create_button_interaction(
      discord_event.id,
      "dps",
      discord_event.channel_id,
      user_id: fake_discord_user_id,
      token: unique_token,
      interaction_id: unique_id
    )
    request_data = create_interaction_request(interaction)

    # Make request
    start_time = Time.now

    app = Rails.application
    env = Rack::MockRequest.env_for(
      "/discord/webhooks",
      method: "POST",
      input: request_data[:body],
      "HTTP_X_SIGNATURE_ED25519" => request_data[:headers]["X-Signature-Ed25519"],
      "HTTP_X_SIGNATURE_TIMESTAMP" => request_data[:headers]["X-Signature-Timestamp"],
      "CONTENT_TYPE" => request_data[:headers]["Content-Type"],
      "HTTP_HOST" => "localhost:5000" # Required for host authorization
    )

    status, headers, body = app.call(env)
    response_body = body.join("")

    end_time = Time.now
    response_time = (end_time - start_time) * 1000 # milliseconds

    results[:response_times] << response_time
    results[:total] += 1

    # Verify response
    if status == 200
      json_response = JSON.parse(response_body)

      if json_response["type"] == 5 # DEFERRED_UPDATE_MESSAGE
        results[:passed] += 1
        puts "  ✓ Passed (Response time: #{response_time.round(2)}ms)"

        # Wait longer for background processing to complete
        # Multiple threads may be running, need to ensure they finish
        max_wait = 2.0
        wait_interval = 0.1
        waited = 0.0
        signup = nil

        while waited < max_wait
          sleep(wait_interval)
          waited += wait_interval

          # Reload event to get fresh data
          discord_event.reload
          signup = discord_event.discord_event_signups.find_by(
            discord_user_id: fake_discord_user_id,
            role: "dps"
          )

          break if signup || waited >= max_wait
        end

        # Verify signup state
        expected_statuses = {
          1 => "on_time",
          2 => "tentative",
          3 => "late",
          4 => "absent",
          5 => nil, # Should be deleted
          6 => "on_time", # Recreated
          7 => "tentative",
          8 => "late",
          9 => "absent",
          10 => nil # Should be deleted
        }

        expected_status = expected_statuses[iteration_num]

        if expected_status.nil?
          # Should be deleted
          if signup
            puts "  ✗ FAILED: Signup should be deleted but still exists (Status: #{signup.status})"
            results[:failed] += 1
            results[:errors] << { iteration: iteration_num, error: "Signup should be deleted but status is #{signup.status}" }
          else
            puts "  ✓ Signup correctly deleted"
          end
        else
          if signup.nil?
            puts "  ✗ FAILED: Signup not found but should exist with status #{expected_status}"
            results[:failed] += 1
            results[:errors] << { iteration: iteration_num, error: "Signup not found but should exist with status #{expected_status}" }
          elsif signup.status == expected_status
            puts "  ✓ Signup status correct: #{signup.status} (expected: #{expected_status})"
          else
            puts "  ✗ FAILED: Signup status is #{signup.status}, expected #{expected_status}"
            results[:failed] += 1
            results[:errors] << { iteration: iteration_num, error: "Status mismatch: got #{signup.status}, expected #{expected_status}" }
          end
        end
      else
        results[:failed] += 1
        error_msg = "Unexpected response type: #{json_response['type']}"
        results[:errors] << { iteration: iteration_num, error: error_msg }
        puts "  ✗ Failed: #{error_msg}"
      end
    else
      results[:failed] += 1
      error_msg = "HTTP status #{status} instead of 200"
      results[:errors] << { iteration: iteration_num, error: error_msg }
      puts "  ✗ Failed: #{error_msg}"
    end

    # Check response time
    if response_time > 3000
      puts "  ⚠ WARNING: Response time (#{response_time.round(2)}ms) exceeds 3 second limit!"
    end

  rescue => e
    results[:failed] += 1
    error_msg = "#{e.class.name}: #{e.message}"
    results[:errors] << { iteration: iteration_num, error: error_msg }
    puts "  ✗ Error: #{error_msg}"
    puts "    #{e.backtrace.first(3).join("\n    ")}"
  end

  puts
  sleep(0.2) # Small delay between iterations
end

# Final summary
puts "=" * 80
puts "TEST SUMMARY"
puts "=" * 80
puts "Total iterations: #{results[:total]}"
puts "Passed: #{results[:passed]}"
puts "Failed: #{results[:failed]}"
puts

if results[:response_times].any?
  avg_time = results[:response_times].sum / results[:response_times].length
  min_time = results[:response_times].min
  max_time = results[:response_times].max

  puts "Response Time Statistics:"
  puts "  Average: #{avg_time.round(2)}ms"
  puts "  Minimum: #{min_time.round(2)}ms"
  puts "  Maximum: #{max_time.round(2)}ms"
  puts
end

if results[:errors].any?
  puts "Errors encountered:"
  results[:errors].each do |error|
    puts "  Iteration #{error[:iteration]}: #{error[:error]}"
  end
  puts
end

# Final verdict
if results[:passed] == 10 && results[:failed] == 0
  puts "✅ ALL TESTS PASSED! Discord webhook interactions are working correctly."
  exit 0
else
  puts "❌ SOME TESTS FAILED. Please review the errors above."
  exit 1
end
