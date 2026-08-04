# frozen_string_literal: true

require "rails_helper"

# Locks in that the logging initializer builds every rolling appender through
# GuildsyncLogging::SafeRollingFile (the ENOENT-safe builder). A future revert to a
# raw Logging.appenders.rolling_file call would reintroduce the deploy log-roll crash,
# so this guards the wiring rather than the runtime behavior (covered elsewhere).
RSpec.describe "config/initializers/logging.rb wiring" do
  let(:source) { File.read(Rails.root.join("config/initializers/logging.rb")) }

  it "never calls Logging.appenders.rolling_file directly" do
    expect(source).not_to match(/Logging\.appenders\.rolling_file/),
      "rolling appenders must be created via GuildsyncLogging::SafeRollingFile#build"
  end

  it "builds all four rolling appenders (rails, sidekiq, puma, discord) via SafeRollingFile" do
    expect(source.scan(/GuildsyncLogging::SafeRollingFile\.new/).size).to eq(4)
  end
end
