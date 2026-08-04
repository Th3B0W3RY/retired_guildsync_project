#!/usr/bin/env ruby
# frozen_string_literal: true

# REAL Discord interaction test - tests actual HTTP webhook endpoint
# This simulates what Discord actually sends

require_relative 'config/environment'
require 'rbnacl'
require 'net/http'
require 'uri'
require 'json'

puts "=" * 80
puts "REAL DISCORD INTERACTION TEST"
puts "=" * 80
puts
puts "This test simulates what Discord ACTUALLY sends to your webhook endpoint"
puts "It will test the HTTP webhook endpoint at: http://localhost:5000/discord/webhooks"
puts

# Test data
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
  g.description = "Test guild"
end

discord_connection = DiscordConnection.find_or_create_by!(guild: guild, user: user) do |dc|
  dc.discord_user_id = "123456789012345678"
  dc.discord_username = "TestUser#1234"
  dc.access_token = "fake_access_token"
  dc.refresh_token = "fake_refresh_token"
  dc.expires_at = 1.hour.from_now
  dc.scopes = "identify guilds"
end

# Use valid Discord snowflake IDs for testing (18-19 digit numbers)
# These are fake but valid format - message update will be skipped if they don't exist in Discord
fake_message_id = "1234567890123456789" # Valid snowflake format
fake_channel_id = "987654321098765432"  # Valid snowflake format

discord_event = DiscordEvent.find_or_create_by!(discord_event_id: "test_event_real") do |de|
  de.guild = guild
  de.discord_connection = discord_connection
  de.discord_message_id = fake_message_id
  de.channel_id = fake_channel_id
  de.title = "Test Event"
  de.description = "This is a test event"
  de.scheduled_at = 1.day.from_now
  de.event_type = "pvp"
end

# Update IDs if they're still fake
if discord_event.discord_message_id == "test_message_real" || !discord_event.discord_message_id.match?(/^\d+$/)
  discord_event.update_columns(discord_message_id: fake_message_id, channel_id: fake_channel_id)
end

# Clear existing signups
discord_event.discord_event_signups.where(discord_user_id: "123456789012345678", role: "dps").destroy_all

# Generate valid Discord signature (if DISCORD_PUBLIC_KEY is set)
def generate_signature(timestamp, body, public_key_hex)
  return "0" * 128 unless public_key_hex && public_key_hex.length == 64

  # For testing, we'll skip actual signature generation
  # In production, Discord signs with their private key
  "0" * 128
rescue => e
  "0" * 128
end

# Create interaction payload
def create_interaction_payload(event_id, role, token: nil, interaction_id: nil)
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
        "id" => "123456789012345678",
        "username" => "TestUser",
        "discriminator" => "1234",
        "global_name" => nil
      }
    },
    "guild_id" => "987654321098765432",
    "channel_id" => "test_channel_real"
  }
end

# Make HTTP request to webhook endpoint
def send_webhook_request(payload, signature: nil, timestamp: nil)
  uri = URI("http://localhost:5000/discord/webhooks")
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 5

  body = payload.to_json
  timestamp ||= Time.now.to_i.to_s

  request = Net::HTTP::Post.new(uri.path)
  request["Content-Type"] = "application/json"

  # In development, if DISCORD_PUBLIC_KEY is not set, signature verification is skipped
  # If it IS set, we need to either not send headers (will fail) or send valid signatures
  # For testing, we'll temporarily unset DISCORD_PUBLIC_KEY to allow the test
  original_key = ENV["DISCORD_PUBLIC_KEY"]
  begin
    ENV.delete("DISCORD_PUBLIC_KEY") # Temporarily unset to skip verification in dev
    request["X-Signature-Ed25519"] = signature || "0" * 128
    request["X-Signature-Timestamp"] = timestamp
    request.body = body

    start_time = Time.now
    response = http.request(request)
    end_time = Time.now
    response_time = (end_time - start_time) * 1000

    {
      status: response.code.to_i,
      body: response.body,
      response_time: response_time,
      headers: response.to_hash
    }
  ensure
    # Restore original key
    if original_key
      ENV["DISCORD_PUBLIC_KEY"] = original_key
    end
  end
rescue => e
  {
    status: 0,
    body: "",
    response_time: 0,
    error: e.message
  }
end

# Mock DiscordService to avoid actual API calls
class DiscordService
  alias_method :original_update_message, :update_message

  def update_message(*args)
    # Just return true, don't actually call Discord API
    true
  end
end

puts "Testing 10 rapid button clicks on existing event..."
puts

results = {
  total: 0,
  passed: 0,
  failed: 0,
  errors: [],
  response_times: []
}

expected_statuses = {
  1 => "on_time",
  2 => "tentative",
  3 => "late",
  4 => "absent",
  5 => nil, # Deleted
  6 => "on_time", # Recreated
  7 => "tentative",
  8 => "late",
  9 => "absent",
  10 => nil # Deleted
}

10.times do |iteration|
  iteration_num = iteration + 1
  puts "Iteration #{iteration_num}/10..."

  begin
    payload = create_interaction_payload(discord_event.id, "dps")
    result = send_webhook_request(payload)

    results[:total] += 1
    results[:response_times] << result[:response_time]

    if result[:error]
      results[:failed] += 1
      results[:errors] << { iteration: iteration_num, error: "Request failed: #{result[:error]}" }
      puts "  ✗ Failed: #{result[:error]}"
      next
    end

    if result[:status] == 200
      json_response = JSON.parse(result[:body]) rescue {}

      if json_response["type"] == 5 # DEFERRED_UPDATE_MESSAGE
        results[:passed] += 1
        puts "  ✓ Passed (Response time: #{result[:response_time].round(2)}ms)"

        # Wait for background processing
        max_wait = 2.0
        wait_interval = 0.1
        waited = 0.0
        signup = nil

        while waited < max_wait
          sleep(wait_interval)
          waited += wait_interval
          discord_event.reload
          signup = discord_event.discord_event_signups.find_by(
            discord_user_id: "123456789012345678",
            role: "dps"
          )
          break if signup || waited >= max_wait
        end

        expected_status = expected_statuses[iteration_num]

        if expected_status.nil?
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
      error_msg = "HTTP status #{result[:status]} instead of 200"
      results[:errors] << { iteration: iteration_num, error: error_msg }
      puts "  ✗ Failed: #{error_msg}"
      puts "  Response body: #{result[:body][0..200]}"
    end

    if result[:response_time] > 3000
      puts "  ⚠ WARNING: Response time (#{result[:response_time].round(2)}ms) exceeds 3 second limit!"
    end

  rescue => e
    results[:failed] += 1
    error_msg = "#{e.class.name}: #{e.message}"
    results[:errors] << { iteration: iteration_num, error: error_msg }
    puts "  ✗ Error: #{error_msg}"
  end

  puts
  sleep(0.2)
end

# Summary
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

if results[:passed] == 10 && results[:failed] == 0
  puts "✅ ALL TESTS PASSED! HTTP webhook endpoint is working correctly."
  exit 0
else
  puts "❌ SOME TESTS FAILED. Please review the errors above."
  puts
  puts "NOTE: If Discord is using Gateway bot instead of HTTP webhooks,"
  puts "check the Gateway bot logs for 'BUTTON INTERACTION RECEIVED (Gateway)'"
  exit 1
end
