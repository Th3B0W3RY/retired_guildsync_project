# frozen_string_literal: true

require "rails_helper"

RSpec.describe Monitoring::Collector do
  describe ".call" do
    it "returns puma metrics without error key when collector runs" do
      data = described_class.call
      expect(data).to have_key(:puma)
      expect(data[:puma]).not_to have_key(:error), "puma metrics should not fail: #{data[:puma].inspect}"
      expect(data[:puma]).to have_key(:workers)
      expect(data[:puma][:workers]).to be_a(Integer)
      expect(data[:puma][:workers]).to be >= 1
    end
  end
end
