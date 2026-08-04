# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guildsync::ExternalRedirectUrl do
  describe ".build!" do
    it "accepts https URLs" do
      expect(described_class.build!("https://example.com/path")).to eq("https://example.com/path")
    end

    it "rejects javascript" do
      expect { described_class.build!("javascript:alert(1)") }.to raise_error(described_class::Invalid)
    end

    it "rejects non-http(s) schemes" do
      expect { described_class.build!("ftp://files.example.com/x") }.to raise_error(described_class::Invalid)
    end

    it "rejects blank" do
      expect { described_class.build!("") }.to raise_error(described_class::Invalid)
      expect { described_class.build!("   ") }.to raise_error(described_class::Invalid)
    end

    it "rejects malformed URIs (e.g. data: with comma)" do
      expect { described_class.build!("data:text/html,<script>x</script>") }.to raise_error(described_class::Invalid)
    end

    it "rejects newlines" do
      expect { described_class.build!("https://a.test/\nLocation: evil") }.to raise_error(described_class::Invalid)
    end

    it "rejects missing host" do
      expect { described_class.build!("https:///nohost") }.to raise_error(described_class::Invalid)
    end
  end
end
