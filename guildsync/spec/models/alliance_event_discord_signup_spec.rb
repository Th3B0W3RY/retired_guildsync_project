# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceEventDiscordSignup, type: :model do
  it "is valid with factory defaults" do
    expect(create(:alliance_event_discord_signup)).to be_valid
  end

  it "enforces unique user per event" do
    signup = create(:alliance_event_discord_signup)
    duplicate = build(:alliance_event_discord_signup,
                      alliance_event: signup.alliance_event,
                      discord_user_id: signup.discord_user_id)

    expect(duplicate).not_to be_valid
  end
end
