# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockedContentFilter do
  before do
    BlockedContentFilter.reset!
    # Stub private load_terms so tests don't depend on config/blocked_content.yml
    allow(BlockedContentFilter).to receive(:load_terms).and_return(%w[badword slurs])
  end

  after { BlockedContentFilter.reset! }

  describe ".blocked?" do
    it "returns false for blank text" do
      expect(described_class.blocked?(nil)).to be false
      expect(described_class.blocked?("")).to be false
      # Whitespace-only is not blank in Rails; we run term check and no term matches, so false
      expect(described_class.blocked?("   ")).to be false
    end

    it "returns true when a blocked term appears as a whole word" do
      expect(described_class.blocked?("This has badword in it")).to be true
      expect(described_class.blocked?("badword")).to be true
      expect(described_class.blocked?("SLURS")).to be true
    end

    it "returns false when text is clean" do
      expect(described_class.blocked?("This is fine")).to be false
      expect(described_class.blocked?("Add dark mode")).to be false
    end

    it "uses word boundaries (does not match inside another word)" do
      expect(described_class.blocked?("badworded")).to be false
      expect(described_class.blocked?("mybadword")).to be false
      expect(described_class.blocked?("Class-based design")).to be false
    end
  end
end
