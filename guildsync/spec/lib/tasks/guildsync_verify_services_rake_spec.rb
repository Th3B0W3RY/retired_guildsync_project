# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "guildsync:verify_services rake task" do
  before do
    Rake::Task.clear
    Rails.application.load_tasks
    allow(GuildsyncLoggers).to receive(:info)
    allow(GuildsyncLoggers).to receive(:warn)
    allow(GuildsyncLoggers).to receive(:error)
  end

  it "runs without raising" do
    Rake::Task["guildsync:verify_services"].reenable
    expect { Rake::Task["guildsync:verify_services"].invoke }.not_to raise_error
  end

  it "does not modify database" do
    Rake::Task["guildsync:verify_services"].reenable
    expect { Rake::Task["guildsync:verify_services"].invoke }.not_to change(Subscription, :count)
  end

  it "invokes and completes, logging to startup_checks" do
    Rake::Task["guildsync:verify_services"].reenable
    Rake::Task["guildsync:verify_services"].invoke
    expect(GuildsyncLoggers).to have_received(:info).with("startup_checks", anything).at_least(:once)
  end
end
