# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorLogger do
  describe ".capture" do
    let(:exception) { StandardError.new("something went wrong") }

    before do
      # Default: only urgent is immediate
      allow(SiteSetting).to receive(:error_immediate_severities).and_return(["urgent"])
    end

    # ── Basic record creation ──────────────────────────────────────────────────

    it "returns nil when given a blank exception" do
      expect(ErrorLogger.capture(nil)).to be_nil
      expect(ErrorLogger.capture("")).to be_nil
    end

    it "returns nil without persisting when given a non-Exception" do
      expect(ErrorDiscordNotifyJob).not_to receive(:perform_later)
      result = nil
      expect { result = ErrorLogger.capture("not an exception") }.not_to change(ErrorLog, :count)
      expect(result).to be_nil
    end

    it "creates and returns an ErrorLog record" do
      result = nil
      expect { result = ErrorLogger.capture(exception) }.to change(ErrorLog, :count).by(1)
      expect(result).to be_a(ErrorLog)
      expect(result).to be_persisted
    end

    it "stores the exception class name" do
      log = ErrorLogger.capture(exception)
      expect(log.error_class).to eq("StandardError")
    end

    it "stores the exception message" do
      log = ErrorLogger.capture(exception)
      expect(log.message).to eq("something went wrong")
    end

    it "stores the backtrace when present" do
      begin
        raise exception
      rescue => e
        log = ErrorLogger.capture(e)
        expect(log.backtrace).to include("error_logger_spec.rb")
      end
    end

    it "defaults severity to 'medium'" do
      log = ErrorLogger.capture(exception)
      expect(log.severity).to eq("medium")
    end

    it "accepts a custom valid severity" do
      log = ErrorLogger.capture(exception, severity: "high")
      expect(log.severity).to eq("high")
    end

    it "falls back to 'medium' for an unrecognized severity string" do
      log = ErrorLogger.capture(exception, severity: "catastrophic")
      expect(log.severity).to eq("medium")
    end

    it "stores optional context" do
      log = ErrorLogger.capture(exception, context: { user_id: 42 })
      expect(log.context["user_id"]).to eq(42)
    end

    it "stores the cause field" do
      log = ErrorLogger.capture(exception, cause: "downstream service timed out")
      expect(log.cause).to eq("downstream service timed out")
    end

    # ── Immediate vs. batched notification ────────────────────────────────────

    context "when the error severity is in error_immediate_severities" do
      before { allow(SiteSetting).to receive(:error_immediate_severities).and_return(["urgent", "high"]) }

      it "enqueues ErrorDiscordNotifyJob immediately for an immediate severity" do
        expect(ErrorDiscordNotifyJob).to receive(:perform_later).once
        ErrorLogger.capture(exception, severity: "urgent")
      end

      it "enqueues ErrorDiscordNotifyJob for every configured immediate severity" do
        expect(ErrorDiscordNotifyJob).to receive(:perform_later).twice
        ErrorLogger.capture(exception, severity: "urgent")
        ErrorLogger.capture(exception, severity: "high")
      end
    end

    context "when the error severity is NOT in error_immediate_severities" do
      it "does not enqueue ErrorDiscordNotifyJob for medium severity" do
        expect(ErrorDiscordNotifyJob).not_to receive(:perform_later)
        ErrorLogger.capture(exception, severity: "medium")
      end

      it "does not enqueue ErrorDiscordNotifyJob for low severity" do
        expect(ErrorDiscordNotifyJob).not_to receive(:perform_later)
        ErrorLogger.capture(exception, severity: "low")
      end
    end

    context "when error_immediate_severities is empty" do
      before { allow(SiteSetting).to receive(:error_immediate_severities).and_return([]) }

      it "never enqueues ErrorDiscordNotifyJob regardless of severity" do
        expect(ErrorDiscordNotifyJob).not_to receive(:perform_later)
        ErrorLogger.capture(exception, severity: "urgent")
      end
    end

    # ── Resilience ────────────────────────────────────────────────────────────

    it "returns nil without raising when ErrorLog persistence fails" do
      allow(ErrorLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "DB gone")
      result = nil
      expect { result = ErrorLogger.capture(exception) }.not_to raise_error
      expect(result).to be_nil
    end
  end
end
