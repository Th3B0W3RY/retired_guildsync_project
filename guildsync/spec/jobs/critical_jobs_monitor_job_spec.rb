# frozen_string_literal: true

require "rails_helper"

RSpec.describe CriticalJobsMonitorJob, type: :job do
  before do
    allow(GuildsyncLoggers).to receive(:info)
    allow(GuildsyncLoggers).to receive(:warn)
    allow(GuildsyncLoggers).to receive(:error)
    # Stub external services so the job runs without Redis/Sidekiq in CI
    allow(Sidekiq).to receive(:redis).and_yield(double("redis", ping: "PONG"))
    stats = instance_double(Sidekiq::Stats, enqueued: 0, processed: 100, failed: 0)
    allow(Sidekiq::Stats).to receive(:new).and_return(stats)
  end

  describe "#perform" do
    it "runs without modifying any data (read-only monitoring)" do
      expect { described_class.new.perform }.not_to change(Subscription, :count)
      expect { described_class.new.perform }.not_to change(User, :count)
    end

    it "logs to GuildsyncLoggers (job_monitoring)" do
      described_class.new.perform
      expect(GuildsyncLoggers).to have_received(:info).with("job_monitoring", anything).at_least(:once)
    end

    it "completes without raising when DB is available" do
      expect { described_class.new.perform }.not_to raise_error
    end

    it "does not enqueue or process any other jobs (monitoring only)" do
      expect(ExpireTrialsJob).not_to receive(:perform_async)
      expect(described_class).not_to receive(:perform_async)
      described_class.new.perform
    end
  end
end
