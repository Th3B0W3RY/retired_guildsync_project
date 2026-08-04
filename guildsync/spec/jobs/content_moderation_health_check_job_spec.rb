# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContentModerationHealthCheckJob, type: :job do
  describe "#perform" do
    def run_job
      described_class.new.perform
    end

    it "runs without errors" do
      expect { run_job }.not_to raise_error
    end

    it "returns a hash with check results" do
      result = run_job
      expect(result).to be_a(Hash)
      expect(result).to have_key(:passed)
      expect(result).to have_key(:check_id)
      expect(result).to have_key(:checks)
      expect(result[:checks]).to be_an(Array)
    end

    it "creates a ModerationHealthCheck record" do
      expect { run_job }.to change(ModerationHealthCheck, :count).by(1)
    end

    it "includes service_health check" do
      result = run_job
      names = result[:checks].map { |c| c[:name] }
      expect(names).to include("service_health", "blocked_words_detection", "false_positives", "moderation_queue", "stuck_items")
    end
  end
end
