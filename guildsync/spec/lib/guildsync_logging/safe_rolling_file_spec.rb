# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "securerandom"

RSpec.describe GuildsyncLogging::SafeRollingFile do
  let(:layout) { Logging.layouts.pattern(pattern: "%m\n") }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = dir
      example.run
    end
  end

  def unique_name
    "test-safe-#{SecureRandom.hex(4)}"
  end

  it "creates the target directory and file, returning a working appender" do
    filename = File.join(@tmp, "nested", "deep", "app.log")

    appender = described_class.new(
      unique_name, filename: filename, layout: layout, keep: 2, age: "daily", safe: true
    ).build

    expect(File).to exist(filename)
    expect(appender).to be_present
  end

  it "retries once when rolling_file raises Errno::ENOENT, then succeeds" do
    filename = File.join(@tmp, "retry.log")
    sentinel = instance_double(Logging::Appenders::RollingFile)
    calls = 0

    allow(Logging.appenders).to receive(:rolling_file) do
      calls += 1
      raise Errno::ENOENT, "missing _copy_" if calls == 1

      sentinel
    end

    result = described_class.new(unique_name, filename: filename, layout: layout).build

    expect(calls).to eq(2)
    expect(result).to be(sentinel)
  end

  it "falls back to a non-rolling file appender after retries are exhausted" do
    filename = File.join(@tmp, "fallback.log")
    fallback = instance_double(Logging::Appenders::File)
    name = unique_name

    allow(Rails.logger).to receive(:warn)
    allow(GuildsyncLoggers).to receive(:warn)
    allow(Logging.appenders).to receive(:rolling_file).and_raise(Errno::ENOENT, "always")
    allow(Logging.appenders).to receive(:file).and_return(fallback)

    result = described_class.new(name, filename: filename, layout: layout).build

    expect(Logging.appenders).to have_received(:rolling_file).twice
    expect(Logging.appenders).to have_received(:file).with(name, filename: filename, layout: layout)
    expect(result).to be(fallback)
  end

  it "emits a durable ops warning to system_warnings on fallback" do
    filename = File.join(@tmp, "warned.log")
    allow(Rails.logger).to receive(:warn)
    allow(GuildsyncLoggers).to receive(:warn)
    allow(Logging.appenders).to receive(:rolling_file).and_raise(Errno::ENOENT, "always")
    allow(Logging.appenders).to receive(:file).and_return(instance_double(Logging::Appenders::File))

    described_class.new(unique_name, filename: filename, layout: layout).build

    expect(GuildsyncLoggers).to have_received(:warn).with(GuildsyncLoggers.system_warnings, /NO rotation/)
  end

  it "ensures the target file exists even when the build path raises first" do
    filename = File.join(@tmp, "ensured.log")
    allow(Rails.logger).to receive(:warn)
    allow(GuildsyncLoggers).to receive(:warn)
    allow(Logging.appenders).to receive(:rolling_file).and_raise(Errno::ENOENT, "always")
    allow(Logging.appenders).to receive(:file).and_return(instance_double(Logging::Appenders::File))

    described_class.new(unique_name, filename: filename, layout: layout).build

    expect(File).to exist(filename)
  end
end
