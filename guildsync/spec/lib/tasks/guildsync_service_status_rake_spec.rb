# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "guildsync:service_status rake task" do
  before do
    Rake::Task.clear
    Rails.application.load_tasks
    allow(PostgresConnectionChecker).to receive(:check!).and_return(true)
    allow(PricingPlanInitializer).to receive(:ensure_plans_exist!).and_return(true)
    allow(GameInitializer).to receive(:ensure_games_exist!).and_return(true)
    allow(RedisConnectionChecker).to receive(:check!).and_return(true)
    allow(SidekiqChecker).to receive(:check!).and_return(true)
    ENV.delete("DISCORD_BOT_TOKEN")
    ENV["DEPLOY_SKIP_DISCORD_GATEWAY_CHECK"] = "1"
  end

  after do
    ENV.delete("DEPLOY_SKIP_DISCORD_GATEWAY_CHECK")
  end

  it "completes when infrastructure checks pass" do
    Rake::Task["guildsync:service_status"].reenable
    expect { Rake::Task["guildsync:service_status"].invoke }.not_to raise_error
  end

  it "aborts when a check returns false" do
    allow(RedisConnectionChecker).to receive(:check!).and_return(false)
    Rake::Task["guildsync:service_status"].reenable
    expect { Rake::Task["guildsync:service_status"].invoke }.to raise_error(SystemExit)
  end
end
