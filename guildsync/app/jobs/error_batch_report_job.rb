# frozen_string_literal: true

# Bundles non-immediate errors into a periodic batch report delivered via Discord.
# Immediate severities (configurable via SiteSetting.error_immediate_severities) are
# excluded — those are still handled by ErrorDiscordNotifyJob in real time.
#
# Report cadence is controlled by SiteSetting.error_batch_cadence_hours (default 24h).
# The period covered starts from the end of the previous report (or cadence_hours ago if
# no prior report exists).
#
# Can be triggered manually from the admin console (triggered_by = "admin:<email>").
class ErrorBatchReportJob < ApplicationJob
  queue_as :default

  MAX_WEBHOOK_CONTENT = 1900
  MAX_DM_LENGTH       = 1800
  DISCORD_CLUSTER_LIMIT = 10

  TREND_LABELS = {
    "new"        => "[NEW]",
    "increasing" => "[UP]",
    "decreasing" => "[DOWN]",
    "stable"     => "[--]"
  }.freeze

  def perform(triggered_by = "scheduled")
    cadence_hours  = SiteSetting.error_batch_cadence_hours
    period_end     = Time.current
    period_start   = compute_period_start(period_end, cadence_hours)
    immediate_sevs = SiteSetting.error_immediate_severities

    errors = ErrorLog
      .where(occurred_at: period_start..period_end)
      .where.not(severity: immediate_sevs)
      .order(:occurred_at)

    clusters   = build_clusters(errors)
    prev_index = build_previous_period_index(period_start, cadence_hours, immediate_sevs)
    annotate_trends(clusters, prev_index)

    summary = {
      "total"               => errors.count,
      "by_severity"         => errors.group_by(&:severity).transform_values(&:count),
      "by_class"            => errors.group_by(&:error_class).transform_values(&:count),
      "new_clusters"        => clusters.count { |c| c["trend"] == "new" },
      "increasing_clusters" => clusters.count { |c| c["trend"] == "increasing" }
    }

    report = ErrorBatchReport.create!(
      period_start:    period_start,
      period_end:      period_end,
      total_errors:    errors.count,
      unique_clusters: clusters.size,
      report_data:     { "clusters" => clusters, "summary" => summary, "period_hours" => cadence_hours },
      triggered_by:    triggered_by.to_s
    )

    if errors.any?
      deliver_report(report)
      report.update!(delivered_at: Time.current)
    end

    Rails.logger.info "[ErrorBatchReportJob] report ##{report.id}: #{errors.count} errors, " \
                      "#{clusters.size} clusters (triggered_by=#{triggered_by})"
  rescue StandardError => e
    Rails.logger.error "[ErrorBatchReportJob] #{e.class}: #{e.message}"
  end

  private

  # ── Period calculation ────────────────────────────────────────────────────────

  def compute_period_start(period_end, cadence_hours)
    last = ErrorBatchReport.order(created_at: :desc).first
    last ? last.period_end : (period_end - cadence_hours.hours)
  end

  # ── Clustering ────────────────────────────────────────────────────────────────

  def build_clusters(errors)
    grouped = errors.group_by { |e| [e.error_class, fingerprint(e.message)] }
    grouped.map do |(error_class, fp), errs|
      {
        "error_class"    => error_class,
        "fingerprint"    => fp,
        "count"          => errs.size,
        "sample_message" => errs.first.message.to_s.truncate(200),
        "first_seen_at"  => errs.first.occurred_at.iso8601,
        "last_seen_at"   => errs.last.occurred_at.iso8601,
        "error_ids"      => errs.first(50).map(&:id),
        "severities"     => errs.group_by(&:severity).transform_values(&:count),
        "trend"          => "stable"
      }
    end.sort_by { |c| -c["count"] }
  end

  # Strips volatile tokens (IDs, UUIDs, timestamps, numbers) to produce a stable
  # grouping key so the same class of error clusters across different parameter values.
  def fingerprint(message)
    msg = message.to_s
    msg = msg.gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, "UUID")
    msg = msg.gsub(/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?)?/, "TIMESTAMP")
    msg = msg.gsub(/\b\d+\b/, "N")
    msg.strip.first(120)
  end

  # ── Trend analysis ────────────────────────────────────────────────────────────

  def build_previous_period_index(period_start, cadence_hours, immediate_sevs)
    prev_end   = period_start
    prev_start = prev_end - cadence_hours.hours
    prev_errors = ErrorLog
      .where(occurred_at: prev_start..prev_end)
      .where.not(severity: immediate_sevs)
      .order(:occurred_at)
    build_clusters(prev_errors).index_by { |c| [c["error_class"], c["fingerprint"]] }
  end

  def annotate_trends(clusters, prev_index)
    clusters.each do |cluster|
      prev = prev_index[[cluster["error_class"], cluster["fingerprint"]]]
      cluster["trend"] = if prev.nil?
        "new"
      elsif cluster["count"] >= prev["count"] * 1.5
        "increasing"
      elsif cluster["count"] <= prev["count"] * 0.5
        "decreasing"
      else
        "stable"
      end
    end
  end

  # ── Discord delivery ──────────────────────────────────────────────────────────

  def deliver_report(report)
    body = build_message(report)
    post_webhook_if_configured(body)
    dm_configured_users(body)
  end

  def build_message(report)
    rd        = report.report_data
    period_h  = rd["period_hours"] || 24
    summary   = rd["summary"] || {}
    total     = summary["total"] || report.total_errors
    clusters  = Array(rd["clusters"])
    new_c     = summary["new_clusters"] || 0
    up_c      = summary["increasing_clusters"] || 0

    lines = []
    lines << "[GuildSync Error Batch Report] — #{period_h}h window ending " \
             "#{report.period_end.strftime("%Y-%m-%d %H:%M")} UTC"
    lines << "#{total} error(s) | #{report.unique_clusters} unique | #{new_c} new | #{up_c} increasing"
    lines << ""

    clusters.first(DISCORD_CLUSTER_LIMIT).each do |c|
      label = TREND_LABELS[c["trend"].to_s] || "[--]"
      lines << "#{label} #{c["error_class"]} x#{c["count"]} — #{c["sample_message"].to_s.truncate(80)}"
    end

    remaining = clusters.size - DISCORD_CLUSTER_LIMIT
    lines << "...and #{remaining} more unique error type(s)" if remaining > 0

    base = ENV["APP_URL"].to_s.presence&.chomp("/")
    if base.present?
      lines << ""
      lines << "#{base}/admin/error-batch-reports/#{report.id}"
    end

    lines.join("\n").truncate(MAX_WEBHOOK_CONTENT)
  end

  def post_webhook_if_configured(body)
    url = ENV["ERROR_NOTIFY_DISCORD_WEBHOOK_URL"].to_s.strip.presence
    return if url.blank?

    payload = { content: body.to_s.truncate(MAX_WEBHOOK_CONTENT) }.to_json
    RestClient.post(url, payload, { "Content-Type" => "application/json" })
    Rails.logger.info "[ErrorBatchReportJob] posted to ERROR_NOTIFY_DISCORD_WEBHOOK_URL"
  rescue StandardError => e
    Rails.logger.error "[ErrorBatchReportJob] webhook failed: #{e.class}: #{e.message}"
  end

  def dm_configured_users(body)
    token = ENV["DISCORD_BOT_TOKEN"].to_s.presence
    if token.blank?
      Rails.logger.info "[ErrorBatchReportJob] DISCORD_BOT_TOKEN not set; skipping DMs"
      return
    end

    usernames = SiteSetting.error_notify_discord_usernames
    if usernames.blank?
      Rails.logger.info "[ErrorBatchReportJob] no usernames configured; skipping DMs"
      return
    end

    service = DiscordService.new(bot_token: token)
    text    = body.to_s.truncate(MAX_DM_LENGTH)
    usernames.each { |raw| send_dm_to(service, normalize_username(raw), text) }
  end

  def normalize_username(raw)
    raw.to_s.strip.split("#").first.to_s.strip
  end

  def send_dm_to(service, username, text)
    if username.blank?
      Rails.logger.warn "[ErrorBatchReportJob] skipping blank username in notify list"
      return
    end

    user = User.where("LOWER(username) = ?", username.downcase).first
    unless user
      Rails.logger.warn "[ErrorBatchReportJob] no GuildSync user #{username.inspect}; skipping"
      return
    end

    discord_id = user.user_discord_connection&.discord_user_id
    unless discord_id.present?
      Rails.logger.warn "[ErrorBatchReportJob] #{username.inspect} has no linked Discord; skipping"
      return
    end

    service.send_dm(discord_id, text)
    Rails.logger.info "[ErrorBatchReportJob] sent DM to @#{username}"
  rescue StandardError => e
    Rails.logger.error "[ErrorBatchReportJob] DM to #{username.inspect} failed: #{e.class}: #{e.message}"
  end
end
