# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guildsync::SafePythonExecutable do
  describe ".resolve!" do
    it "accepts a simple PATH token" do
      expect(described_class.resolve!("python3")).to eq("python3")
    end

    it "rejects shell metacharacters" do
      expect { described_class.resolve!("python3;rm -rf /") }.to raise_error(
        described_class::InvalidExecutable
      )
    end

    it "rejects path traversal" do
      expect { described_class.resolve!("../../bin/python3") }.to raise_error(
        described_class::InvalidExecutable
      )
    end

    it "requires an existing executable for absolute paths" do
      expect { described_class.resolve!("/nonexistent/python_xyz") }.to raise_error(
        described_class::InvalidExecutable, /not found/
      )
    end

    it "resolves a real executable path" do
      which = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).find do |dir|
        File.executable?(File.join(dir, "ruby"))
      end
      skip "no ruby in PATH" unless which

      path = File.join(which, "ruby")
      expect(described_class.resolve!(path)).to eq(File.expand_path(path))
    end
  end
end
