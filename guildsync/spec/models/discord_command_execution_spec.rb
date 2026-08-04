# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordCommandExecution, type: :model do
  describe ".claim!" do
    it "creates a pending execution record" do
      exec = described_class.claim!("tok_1", "process_create")
      expect(exec).to be_persisted
      expect(exec.status).to eq("pending")
    end

    it "returns nil on duplicate claim (unique index)" do
      described_class.claim!("tok_2", "process_create")
      duplicate = described_class.claim!("tok_2", "process_create")
      expect(duplicate).to be_nil
    end

    it "allows different keys on same token" do
      described_class.claim!("tok_3", "process_create")
      exec2 = described_class.claim!("tok_3", "process_close")
      expect(exec2).to be_persisted
    end
  end

  describe ".already_processed?" do
    it "returns false for non-existent records" do
      expect(described_class.already_processed?("tok_x", "process_create")).to be false
    end

    it "returns false for pending records" do
      described_class.claim!("tok_4", "process_create")
      expect(described_class.already_processed?("tok_4", "process_create")).to be false
    end

    it "returns true for completed records" do
      exec = described_class.claim!("tok_5", "process_create")
      exec.mark_completed!
      expect(described_class.already_processed?("tok_5", "process_create")).to be true
    end
  end

  describe "#mark_completed!" do
    it "updates status and sets completed_at" do
      exec = described_class.claim!("tok_6", "process_create")
      exec.mark_completed!
      exec.reload
      expect(exec.status).to eq("completed")
      expect(exec.completed_at).to be_present
    end
  end

  describe "#mark_failed!" do
    it "updates status to failed" do
      exec = described_class.claim!("tok_7", "process_create")
      exec.mark_failed!
      expect(exec.reload.status).to eq("failed")
    end
  end
end
