# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorBatchReportJob, type: :job do
  # ── Test helpers ─────────────────────────────────────────────────────────────

  # Creates a real ErrorLog row with sensible defaults
  def make_error(error_class: "StandardError", message: "something failed", severity: "medium", occurred_at: 1.hour.ago)
    ErrorLog.create!(
      error_class: error_class,
      message: message,
      occurred_at: occurred_at,
      severity: severity
    )
  end

  before do
    allow(SiteSetting).to receive(:error_immediate_severities).and_return(["urgent"])
    allow(SiteSetting).to receive(:error_batch_cadence_hours).and_return(24)
    # Silence external calls by default
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return(nil)
    allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("APP_URL").and_return(nil)
  end

  # ── Report creation ───────────────────────────────────────────────────────────

  describe "report record" do
    it "creates exactly one ErrorBatchReport per run" do
      expect { described_class.perform_now }.to change(ErrorBatchReport, :count).by(1)
    end

    it "stores triggered_by from the argument" do
      described_class.perform_now("admin:ops@example.com")
      expect(ErrorBatchReport.last.triggered_by).to eq("admin:ops@example.com")
    end

    it "defaults triggered_by to 'scheduled'" do
      described_class.perform_now
      expect(ErrorBatchReport.last.triggered_by).to eq("scheduled")
    end

    it "does not raise when internal processing fails" do
      allow(ErrorBatchReport).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "DB gone")
      expect { described_class.perform_now }.not_to raise_error
    end
  end

  # ── Period calculation ────────────────────────────────────────────────────────

  describe "period coverage" do
    it "covers the configured cadence when no prior report exists" do
      described_class.perform_now
      report = ErrorBatchReport.last
      expect(report.duration_hours).to be_within(0.1).of(24.0)
    end

    it "starts from the previous report's period_end rather than cadence ago" do
      prior = create(:error_batch_report, period_end: 6.hours.ago)
      described_class.perform_now
      new_report = ErrorBatchReport.order(:created_at).last
      expect(new_report.period_start).to be_within(1.second).of(prior.period_end)
    end

    it "ends at approximately the current time" do
      described_class.perform_now
      expect(ErrorBatchReport.last.period_end).to be_within(5.seconds).of(Time.current)
    end
  end

  # ── Error filtering ───────────────────────────────────────────────────────────

  describe "error filtering" do
    it "excludes errors whose severity is in error_immediate_severities" do
      make_error(severity: "urgent")
      make_error(severity: "medium")
      described_class.perform_now
      expect(ErrorBatchReport.last.total_errors).to eq(1)
    end

    it "includes low, medium, high, and stable severity errors" do
      %w[low medium high stable].each { |sev| make_error(severity: sev) }
      described_class.perform_now
      expect(ErrorBatchReport.last.total_errors).to eq(4)
    end

    it "excludes errors that occurred before the period window" do
      make_error(occurred_at: 48.hours.ago) # outside 24 h cadence
      described_class.perform_now
      expect(ErrorBatchReport.last.total_errors).to eq(0)
    end

    it "respects a custom error_immediate_severities setting" do
      allow(SiteSetting).to receive(:error_immediate_severities).and_return(["urgent", "high"])
      make_error(severity: "high")
      make_error(severity: "medium")
      described_class.perform_now
      expect(ErrorBatchReport.last.total_errors).to eq(1)
    end
  end

  # ── Clustering ────────────────────────────────────────────────────────────────

  describe "error clustering" do
    it "groups errors with the same class and similar message into one cluster" do
      make_error(error_class: "NoMethodError", message: "undefined method 'foo' for nil with id=1")
      make_error(error_class: "NoMethodError", message: "undefined method 'foo' for nil with id=999")
      described_class.perform_now
      report = ErrorBatchReport.last
      expect(report.unique_clusters).to eq(1)
      expect(report.clusters.first["count"]).to eq(2)
    end

    it "creates separate clusters for different error classes" do
      make_error(error_class: "NoMethodError", message: "boom")
      make_error(error_class: "RuntimeError",  message: "boom")
      described_class.perform_now
      expect(ErrorBatchReport.last.unique_clusters).to eq(2)
    end

    it "creates separate clusters for meaningfully different messages within the same class" do
      make_error(error_class: "ArgumentError", message: "wrong number of arguments (given 2, expected 1)")
      make_error(error_class: "ArgumentError", message: "invalid value for Integer")
      described_class.perform_now
      expect(ErrorBatchReport.last.unique_clusters).to eq(2)
    end

    it "sorts clusters by count descending so the most frequent appears first" do
      3.times { make_error(error_class: "RuntimeError", message: "frequent error") }
      1.times { make_error(error_class: "StandardError", message: "rare error") }
      described_class.perform_now
      counts = ErrorBatchReport.last.clusters.map { |c| c["count"] }
      expect(counts).to eq(counts.sort.reverse)
    end

    it "stores a sample message from the first error in the cluster" do
      make_error(error_class: "StandardError", message: "first occurrence message")
      make_error(error_class: "StandardError", message: "first occurrence message")
      described_class.perform_now
      expect(ErrorBatchReport.last.clusters.first["sample_message"]).to include("first occurrence message")
    end

    it "caps stored error IDs at 50 per cluster to bound JSON size" do
      55.times { make_error(error_class: "StandardError", message: "same message") }
      described_class.perform_now
      expect(ErrorBatchReport.last.clusters.first["error_ids"].size).to eq(50)
    end

    it "records severity breakdown per cluster" do
      make_error(error_class: "StandardError", message: "msg", severity: "medium")
      make_error(error_class: "StandardError", message: "msg", severity: "low")
      described_class.perform_now
      severities = ErrorBatchReport.last.clusters.first["severities"]
      expect(severities).to eq("medium" => 1, "low" => 1)
    end
  end

  # ── Fingerprinting ────────────────────────────────────────────────────────────

  describe "message fingerprinting" do
    it "groups errors that differ only by a bare integer ID" do
      make_error(message: "Couldn't find User with id=1")
      make_error(message: "Couldn't find User with id=999")
      described_class.perform_now
      expect(ErrorBatchReport.last.unique_clusters).to eq(1)
    end

    it "groups errors that differ only by a UUID" do
      make_error(message: "Token a1b2c3d4-e5f6-7890-abcd-ef1234567890 expired")
      make_error(message: "Token 00000000-0000-0000-0000-000000000001 expired")
      described_class.perform_now
      expect(ErrorBatchReport.last.unique_clusters).to eq(1)
    end

    it "groups errors that differ only by an ISO timestamp" do
      make_error(message: "Job queued at 2026-04-01T12:00:00Z failed")
      make_error(message: "Job queued at 2026-04-09T08:30:00Z failed")
      described_class.perform_now
      expect(ErrorBatchReport.last.unique_clusters).to eq(1)
    end
  end

  # ── Trend analysis ────────────────────────────────────────────────────────────

  describe "trend analysis" do
    it "marks a cluster 'new' when it has no match in the previous period" do
      make_error(error_class: "BrandNewError", message: "fresh", occurred_at: 1.hour.ago)
      described_class.perform_now
      cluster = ErrorBatchReport.last.clusters.find { |c| c["error_class"] == "BrandNewError" }
      expect(cluster["trend"]).to eq("new")
    end

    it "marks a cluster 'increasing' when count is >= 1.5x the previous period" do
      # 2 occurrences in previous period
      2.times { make_error(error_class: "GrowingError", message: "grow", occurred_at: 30.hours.ago) }
      # 4 occurrences in current period (2x)
      4.times { make_error(error_class: "GrowingError", message: "grow", occurred_at: 1.hour.ago) }
      described_class.perform_now
      cluster = ErrorBatchReport.last.clusters.find { |c| c["error_class"] == "GrowingError" }
      expect(cluster["trend"]).to eq("increasing")
    end

    it "marks a cluster 'decreasing' when count is <= 0.5x the previous period" do
      # 4 occurrences in previous period
      4.times { make_error(error_class: "FadingError", message: "fade", occurred_at: 30.hours.ago) }
      # 1 occurrence in current period (0.25x)
      make_error(error_class: "FadingError", message: "fade", occurred_at: 1.hour.ago)
      described_class.perform_now
      cluster = ErrorBatchReport.last.clusters.find { |c| c["error_class"] == "FadingError" }
      expect(cluster["trend"]).to eq("decreasing")
    end

    it "marks a cluster 'stable' when count is close to the previous period" do
      # 3 in previous, 3 in current → exactly 1.0x → stable
      3.times { make_error(error_class: "SteadyError", message: "steady", occurred_at: 30.hours.ago) }
      3.times { make_error(error_class: "SteadyError", message: "steady", occurred_at: 1.hour.ago) }
      described_class.perform_now
      cluster = ErrorBatchReport.last.clusters.find { |c| c["error_class"] == "SteadyError" }
      expect(cluster["trend"]).to eq("stable")
    end
  end

  # ── Summary ───────────────────────────────────────────────────────────────────

  describe "summary data" do
    it "records the total number of matching errors" do
      3.times { make_error }
      described_class.perform_now
      expect(ErrorBatchReport.last.summary["total"]).to eq(3)
    end

    it "breaks down errors by severity" do
      2.times { make_error(severity: "medium") }
      1.times { make_error(severity: "low") }
      described_class.perform_now
      by_sev = ErrorBatchReport.last.summary["by_severity"]
      expect(by_sev["medium"]).to eq(2)
      expect(by_sev["low"]).to eq(1)
    end

    it "counts new clusters in summary" do
      make_error(error_class: "UniqueToThisRun", message: "never before seen")
      described_class.perform_now
      expect(ErrorBatchReport.last.summary["new_clusters"]).to eq(1)
    end

    it "counts increasing clusters in summary" do
      2.times { make_error(error_class: "RisingError", message: "rise", occurred_at: 30.hours.ago) }
      4.times { make_error(error_class: "RisingError", message: "rise", occurred_at: 1.hour.ago) }
      described_class.perform_now
      expect(ErrorBatchReport.last.summary["increasing_clusters"]).to eq(1)
    end
  end

  # ── Discord delivery ──────────────────────────────────────────────────────────

  describe "Discord delivery" do
    context "when errors exist in the period" do
      before { make_error }

      it "posts to the webhook when ERROR_NOTIFY_DISCORD_WEBHOOK_URL is configured" do
        allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return("https://hook.example.com")
        expect(RestClient).to receive(:post).with(
          "https://hook.example.com",
          a_string_including("[GuildSync Error Batch Report]"),
          hash_including("Content-Type" => "application/json")
        )
        described_class.perform_now
      end

      it "includes the error class name in the webhook body" do
        allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return("https://hook.example.com")
        captured = nil
        allow(RestClient).to receive(:post) { |_, body, _| captured = body }
        make_error(error_class: "SpecificError", message: "very specific")
        described_class.perform_now
        expect(captured).to include("SpecificError")
      end

      it "includes a report link when APP_URL is set" do
        allow(ENV).to receive(:[]).with("APP_URL").and_return("https://app.example.com")
        allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return("https://hook.example.com")
        captured = nil
        allow(RestClient).to receive(:post) { |_, body, _| captured = body }
        described_class.perform_now
        expect(captured).to include("app.example.com/admin/error-batch-reports/")
      end

      it "sends a DM to Discord-linked users in the notify list" do
        allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("bot-token")
        user = create(:user, username: "batchreport_admin")
        create(:user_discord_connection, user: user, discord_user_id: "111222333444555666")
        allow(SiteSetting).to receive(:error_notify_discord_usernames).and_return(["batchreport_admin"])

        svc = instance_double(DiscordService, send_dm: true)
        allow(DiscordService).to receive(:new).with(bot_token: "bot-token").and_return(svc)

        described_class.perform_now

        expect(svc).to have_received(:send_dm).with(
          "111222333444555666",
          a_string_including("[GuildSync Error Batch Report]")
        )
      end

      it "sets delivered_at on the report after successful delivery" do
        allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return("https://hook.example.com")
        allow(RestClient).to receive(:post)
        described_class.perform_now
        expect(ErrorBatchReport.last.delivered_at).not_to be_nil
      end

      it "skips DMs when DISCORD_BOT_TOKEN is not set" do
        allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return(nil)
        expect(DiscordService).not_to receive(:new)
        described_class.perform_now
      end
    end

    context "when no errors exist in the period" do
      it "does not post to the webhook" do
        allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return("https://hook.example.com")
        expect(RestClient).not_to receive(:post)
        described_class.perform_now
      end

      it "leaves delivered_at nil on the saved report" do
        described_class.perform_now
        expect(ErrorBatchReport.last.delivered_at).to be_nil
      end
    end

    it "rescues webhook errors without raising" do
      make_error
      allow(ENV).to receive(:[]).with("ERROR_NOTIFY_DISCORD_WEBHOOK_URL").and_return("https://hook.example.com")
      allow(RestClient).to receive(:post).and_raise(StandardError, "network timeout")
      expect { described_class.perform_now }.not_to raise_error
    end

    it "rescues DM send errors without raising" do
      make_error
      allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("bot-token")
      user = create(:user, username: "dm_fail_user")
      create(:user_discord_connection, user: user, discord_user_id: "888")
      allow(SiteSetting).to receive(:error_notify_discord_usernames).and_return(["dm_fail_user"])

      svc = instance_double(DiscordService)
      allow(svc).to receive(:send_dm).and_raise(StandardError, "discord is down")
      allow(DiscordService).to receive(:new).and_return(svc)

      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
