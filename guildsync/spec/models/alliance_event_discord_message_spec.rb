# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceEventDiscordMessage, type: :model do
  it "is valid with factory defaults" do
    expect(create(:alliance_event_discord_message)).to be_valid
  end

  it "enforces one message link per guild per alliance event" do
    link = create(:alliance_event_discord_message)
    duplicate = build(:alliance_event_discord_message, alliance_event: link.alliance_event, guild: link.guild)

    expect(duplicate).not_to be_valid
  end
end
