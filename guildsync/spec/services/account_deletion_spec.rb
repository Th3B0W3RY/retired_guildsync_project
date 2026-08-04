# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountDeletion do
  describe ".feature_enabled?" do
    around do |example|
      previous = ENV["ACCOUNT_SELF_DELETE_ENABLED"]
      example.run
      if previous.nil?
        ENV.delete("ACCOUNT_SELF_DELETE_ENABLED")
      else
        ENV["ACCOUNT_SELF_DELETE_ENABLED"] = previous
      end
    end

    it "is true in test regardless of ACCOUNT_SELF_DELETE_ENABLED" do
      ENV["ACCOUNT_SELF_DELETE_ENABLED"] = "0"
      expect(described_class.feature_enabled?).to be true
    end

    context "when Rails.env.production? is true" do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it "is true when ACCOUNT_SELF_DELETE_ENABLED is unset" do
        ENV.delete("ACCOUNT_SELF_DELETE_ENABLED")
        expect(described_class.feature_enabled?).to be true
      end

      it "is true when ACCOUNT_SELF_DELETE_ENABLED is 1" do
        ENV["ACCOUNT_SELF_DELETE_ENABLED"] = "1"
        expect(described_class.feature_enabled?).to be true
      end

      it "is false when ACCOUNT_SELF_DELETE_ENABLED is 0" do
        ENV["ACCOUNT_SELF_DELETE_ENABLED"] = "0"
        expect(described_class.feature_enabled?).to be false
      end
    end
  end
end
