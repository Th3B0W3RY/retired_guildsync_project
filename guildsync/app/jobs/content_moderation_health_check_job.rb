# frozen_string_literal: true

# Sidekiq worker (not ActiveJob): enqueue with `perform_async` only.
# Runs every 6 hours to verify content moderation filter and queue health.
# Logs to moderation_health.txt and stores results in ModerationHealthCheck.
# No SMTP/email; alerts via Rails.logger and GuildsyncLoggers only.
class ContentModerationHealthCheckJob
  include Sidekiq::Worker

  sidekiq_options retry: 2, queue: :default

  MODERATION_LOG = "moderation_health"

  def perform
    log("info", "Starting Content Moderation Health Check (6-hour scheduled job)")
    results = {
      timestamp: Time.current,
      check_id: SecureRandom.uuid,
      checks: [],
      passed: true,
      warning_count: 0,
      fail_count: 0,
      next_run: 6.hours.from_now
    }

    results[:checks] << check_service_health
    results[:checks] << check_blocked_words_detection
    results[:checks] << check_false_positives
    results[:checks] << check_moderation_queue
    results[:checks] << check_stuck_items

    results[:passed] = results[:checks].all? { |c| c[:status] == "pass" }
    results[:warning_count] = results[:checks].count { |c| c[:status] == "warning" }
    results[:fail_count] = results[:checks].count { |c| c[:status] == "fail" }

    if !results[:passed] || results[:warning_count].positive?
      send_moderation_alert(results)
    end

    log("info", "Content Moderation Health Check complete. Passed: #{results[:passed]}, Warnings: #{results[:warning_count]}, Fails: #{results[:fail_count]}")

    ModerationHealthCheck.create!(
      check_id: results[:check_id],
      passed: results[:passed],
      warning_count: results[:warning_count],
      fail_count: results[:fail_count],
      details: results[:checks].index_with { |c| c.stringify_keys },
      next_run: results[:next_run]
    )

    Rails.cache.write("moderation:last_health_check", results, expires_in: 7.hours)
    results
  end

  private

  def log(level, message)
    GuildsyncLoggers.public_send(level, MODERATION_LOG, message) if defined?(GuildsyncLoggers)
    Rails.logger.public_send(level, "ContentModerationHealthCheck: #{message}")
  end

  def check_service_health
    start_time = Time.current
    service = ContentModeration::FilterService.new("test content for health check #{Time.current.to_i}", content_type: "HealthCheck", user: nil)
    service.process
    response_time = Time.current - start_time
    if response_time > 5
      { name: "service_health", status: "fail", message: "Service response time critical: #{response_time.round(2)}s", response_time: response_time }
    elsif response_time > 3
      { name: "service_health", status: "warning", message: "Service response time slow: #{response_time.round(2)}s", response_time: response_time }
    else
      { name: "service_health", status: "pass", message: "Service healthy, response time: #{response_time.round(2)}s", response_time: response_time }
    end
  rescue => e
    { name: "service_health", status: "fail", message: "Service failed: #{e.message}", error: e.message }
  end

  def check_blocked_words_detection
    test_cases = [
      { input: "This is clean content here", expected: false },
      { input: "clean text only", expected: false }
    ]
    # Add one expected-trigger if we have a known blocked term from YAML/DB
    terms = BlockedContentFilter.terms
    if terms.any?
      test_cases << { input: "This has #{terms.first} in it", expected: true }
    end
    failed = []
    test_cases.each do |test|
      triggered = BlockedContentFilter.scan(test[:input])
      hit = triggered.any?
      failed << test.merge(got: hit) if hit != test[:expected]
    end
    detection_rate = ((test_cases.size - failed.size).to_f / test_cases.size * 100).round(2)
    if failed.any?
      status = detection_rate >= 80 ? "warning" : "fail"
      { name: "blocked_words_detection", status: status, message: "Detection rate: #{detection_rate}%", detection_rate: detection_rate, failed_tests: failed }
    else
      { name: "blocked_words_detection", status: "pass", message: "All test cases passed", detection_rate: 100 }
    end
  end

  def check_false_positives
    test_cases = [
      "The quick brown fox jumps over the lazy dog",
      "Thank you for this amazing feature!",
      "I need help with my guild settings"
    ]
    false_positives = test_cases.select { |text| BlockedContentFilter.scan(text).any? }
    if false_positives.any?
      { name: "false_positives", status: "warning", message: "Found #{false_positives.size} potential false positives", count: false_positives.size }
    else
      { name: "false_positives", status: "pass", message: "No false positives detected" }
    end
  end

  def check_moderation_queue
    pending = FeatureRequest.pending_review.count + FeatureRequestComment.pending_review.count
    status = "pass"
    message = "Queue healthy"
    status = "warning" if pending > 100
    status = "fail" if pending > 200
    message = "Pending count: #{pending}" if pending > 50
    { name: "moderation_queue", status: status, message: message, pending_count: pending }
  end

  def check_stuck_items
    threshold = 48.hours.ago
    stuck_r = FeatureRequest.pending_review.where("created_at < ?", threshold).count
    stuck_c = FeatureRequestComment.pending_review.where("created_at < ?", threshold).count
    total = stuck_r + stuck_c
    status = total > 20 ? "fail" : (total > 5 ? "warning" : "pass")
    message = total > 0 ? "#{total} items stuck in moderation >48h" : "No stuck items"
    { name: "stuck_items", status: status, message: message, stuck_requests: stuck_r, stuck_comments: stuck_c, total_stuck: total }
  end

  def send_moderation_alert(results)
    log("warn", "MODERATION HEALTH: #{results[:fail_count]} fails, #{results[:warning_count]} warnings")
    Rails.logger.error("Content Moderation Health Check failed: #{results[:checks].select { |c| c[:status] == 'fail' }.map { |c| c[:name] }.join(', ')}") unless results[:passed]
  end
end
