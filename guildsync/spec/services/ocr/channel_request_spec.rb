# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ocr::ChannelRequest do
  describe ".for_discord_gear_upload" do
    it "sets a stable Discord user_agent and leaves IP blank" do
      req = described_class.for_discord_gear_upload
      expect(req.user_agent).to eq("Discord/gear-upload")
      expect(req.remote_ip).to be_nil
    end
  end
end
