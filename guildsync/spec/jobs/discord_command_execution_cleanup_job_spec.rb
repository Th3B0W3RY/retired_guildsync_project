# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordCommandExecutionCleanupJob, type: :job do
  describe "#perform" do
    it "deletes executions older than 24 hours" do
      old = DiscordCommandExecution.create!(
        interaction_token: "tok_old", command_key: "process_create",
        status: "completed", created_at: 25.hours.ago
      )
      recent = DiscordCommandExecution.create!(
        interaction_token: "tok_recent", command_key: "process_create",
        status: "completed", created_at: 1.hour.ago
      )

      described_class.new.perform

      expect(DiscordCommandExecution.find_by(id: old.id)).to be_nil
      expect(DiscordCommandExecution.find_by(id: recent.id)).to be_present
    end

    it "deletes failed and pending rows older than 24 hours" do
      failed = DiscordCommandExecution.create!(
        interaction_token: "tok_fail", command_key: "process_close",
        status: "failed", created_at: 2.days.ago
      )
      pending_exec = DiscordCommandExecution.create!(
        interaction_token: "tok_pend", command_key: "process_invite",
        status: "pending", created_at: 26.hours.ago
      )

      described_class.new.perform

      expect(DiscordCommandExecution.find_by(id: failed.id)).to be_nil
      expect(DiscordCommandExecution.find_by(id: pending_exec.id)).to be_nil
    end

    it "leaves all rows intact when none are stale" do
      DiscordCommandExecution.create!(
        interaction_token: "tok_fresh", command_key: "process_create",
        status: "completed", created_at: 30.minutes.ago
      )

      expect { described_class.new.perform }.not_to change(DiscordCommandExecution, :count)
    end

    it "handles an empty table gracefully" do
      expect { described_class.new.perform }.not_to raise_error
    end
  end
end
