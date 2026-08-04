# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordCommandJob, type: :job do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let(:user)  { create(:user) }
  let!(:membership) { guild.guild_members.create!(user: user, role: :member, status: :active) }

  # =========================================================================
  # Handler configuration
  # =========================================================================
  describe "retry/discard configuration" do
    it "discards on ActiveRecord::RecordNotFound" do
      handlers = described_class.rescue_handlers.map(&:first)
      expect(handlers).to include("ActiveRecord::RecordNotFound")
    end

    it "discards on ActiveJob::DeserializationError" do
      handlers = described_class.rescue_handlers.map(&:first)
      expect(handlers).to include("ActiveJob::DeserializationError")
    end

    it "retries on transient network errors only" do
      retry_handler = described_class.rescue_handlers.find { |h| h.first.include?("RestClient::RequestTimeout") }
      expect(retry_handler).to be_present
    end

    it "does not retry on generic StandardError" do
      retry_handler = described_class.rescue_handlers.find { |h| h.first == "StandardError" }
      expect(retry_handler).to be_nil
    end
  end

  # =========================================================================
  # Non-retryable errors are not swallowed
  # =========================================================================
  describe "non-retryable error handling" do
    before do
      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
    end

    let(:boom_klass) do
      Class.new do
        def process_fail(_opts)
          raise "application-level bug"
        end
      end
    end

    before { stub_const("DummyBoomService", boom_klass) }

    it "logs and does not re-raise non-retryable errors" do
      expect(Rails.logger).to receive(:error).with(/Non-retryable error/)

      expect do
        described_class.new.perform(
          "DummyBoomService", "process_fail", "tok_abc",
          guild.id, user.id, {}
        )
      end.not_to raise_error
    end

    it "marks the idempotency execution as failed" do
      described_class.new.perform(
        "DummyBoomService", "process_fail", "tok_mark_fail",
        guild.id, user.id, {}
      )

      exec = DiscordCommandExecution.find_by(interaction_token: "tok_mark_fail")
      expect(exec.status).to eq("failed")
    end
  end

  describe "service/method guards" do
    let(:service_klass) do
      Class.new do
        def process_action(_opts); end
      end
    end

    before { stub_const("DummyGuardService", service_klass) }

    it "marks execution failed when service class is invalid" do
      described_class.new.perform(
        "NopeService",
        "process_action",
        "tok_bad_service",
        guild.id,
        user.id,
        {}
      )

      exec = DiscordCommandExecution.find_by(interaction_token: "tok_bad_service")
      expect(exec.status).to eq("failed")
    end

    it "marks execution failed when method name is not an allowed command handler" do
      described_class.new.perform(
        "DummyGuardService",
        "destroy_all",
        "tok_bad_method",
        guild.id,
        user.id,
        {}
      )

      exec = DiscordCommandExecution.find_by(interaction_token: "tok_bad_method")
      expect(exec.status).to eq("failed")
    end
  end

  # =========================================================================
  # Claim race condition
  # =========================================================================
  describe "claim returns nil (another process won)" do
    let(:ok_klass) do
      Class.new do
        @called = false
        class << self; attr_accessor :called; end
        def process_action(_opts); self.class.called = true; end
      end
    end

    before { stub_const("DummyOkService", ok_klass) }

    it "does not execute the service when claim is already taken" do
      DiscordCommandExecution.create!(interaction_token: "tok_race", command_key: "process_action", status: "pending")
      DummyOkService.called = false

      described_class.new.perform(
        "DummyOkService", "process_action", "tok_race",
        guild.id, user.id, {}
      )
      expect(DummyOkService.called).to be false
    end
  end

  # =========================================================================
  # RecordNotFound rescue path
  # =========================================================================
  describe "RecordNotFound rescue path" do
    let(:ok_klass) do
      Class.new { def process_action(_opts); end }
    end

    before { stub_const("DummyNoop", ok_klass) }

    it "marks execution as failed and re-raises when guild is missing" do
      expect {
        described_class.new.perform(
          "DummyNoop", "process_action", "tok_rnf",
          -1, user.id, {}
        )
      }.to raise_error(ActiveRecord::RecordNotFound)

      exec = DiscordCommandExecution.find_by(interaction_token: "tok_rnf")
      expect(exec.status).to eq("failed")
    end
  end

  # =========================================================================
  # Retryable error rescue path
  # =========================================================================
  describe "retryable error rescue path" do
    let(:timeout_klass) do
      Class.new do
        def process_action(_opts)
          raise RestClient::RequestTimeout
        end
      end
    end

    before { stub_const("DummyTimeoutService", timeout_klass) }

    it "marks execution as failed and re-raises" do
      expect {
        described_class.new.perform(
          "DummyTimeoutService", "process_action", "tok_retry",
          guild.id, user.id, {}
        )
      }.to raise_error(RestClient::RequestTimeout)

      exec = DiscordCommandExecution.find_by(interaction_token: "tok_retry")
      expect(exec.status).to eq("failed")
    end
  end

  # =========================================================================
  # Blank interaction token
  # =========================================================================
  describe "blank interaction token" do
    before do
      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
    end

    let(:boom_klass) do
      Class.new do
        def process_fail(_opts)
          raise "bug"
        end
      end
    end

    before { stub_const("DummyBlankTokenService", boom_klass) }

    it "does not attempt error follow-up when token is blank" do
      described_class.new.perform(
        "DummyBlankTokenService", "process_fail", "",
        guild.id, user.id, {}
      )

      expect(WebMock).not_to have_requested(:post, %r{discord\.com/api/v10/webhooks})
    end
  end

  # =========================================================================
  # Idempotency
  # =========================================================================
  describe "idempotency" do
    let(:counter_klass) do
      Class.new do
        @call_count = 0
        class << self; attr_accessor :call_count; end

        def process_action(_opts)
          self.class.call_count += 1
        end
      end
    end

    before do
      stub_const("DummyCounterService", counter_klass)
      DummyCounterService.call_count = 0
    end

    it "executes the command on first invocation" do
      described_class.new.perform(
        "DummyCounterService", "process_action", "tok_first",
        guild.id, user.id, {}
      )
      expect(DummyCounterService.call_count).to eq(1)
      expect(DiscordCommandExecution.find_by(interaction_token: "tok_first").status).to eq("completed")
    end

    it "skips execution on duplicate invocation with same token" do
      described_class.new.perform(
        "DummyCounterService", "process_action", "tok_dup",
        guild.id, user.id, {}
      )
      described_class.new.perform(
        "DummyCounterService", "process_action", "tok_dup",
        guild.id, user.id, {}
      )

      expect(DummyCounterService.call_count).to eq(1)
    end

    it "allows different command keys on the same interaction token" do
      described_class.new.perform(
        "DummyCounterService", "process_action", "tok_multi",
        guild.id, user.id, {}
      )

      other_klass = Class.new do
        def process_other(_opts); end
      end
      stub_const("DummyCounterService2", other_klass)

      expect do
        described_class.new.perform(
          "DummyCounterService2", "process_other", "tok_multi",
          guild.id, user.id, {}
        )
      end.not_to raise_error
    end
  end
end
