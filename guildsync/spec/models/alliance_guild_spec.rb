# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceGuild, type: :model do
  let(:guild) { create(:guild) }
  let(:alliance1) { create(:alliance, leader_guild: guild, leader_user: guild.owner) }
  let(:alliance2) { create(:alliance) }

  it "allows only one active alliance per guild" do
    create(:alliance_guild, alliance: alliance1, guild: guild, status: :active)
    duplicate_active = build(:alliance_guild, alliance: alliance2, guild: guild, status: :active)

    expect(duplicate_active).not_to be_valid
    expect(duplicate_active.errors[:guild_id]).to include("already belongs to an active alliance")
  end

  it "allows historical non-active records for the same guild" do
    create(:alliance_guild, alliance: alliance1, guild: guild, status: :left)
    active_record = build(:alliance_guild, alliance: alliance2, guild: guild, status: :active)

    expect(active_record).to be_valid
  end
end
