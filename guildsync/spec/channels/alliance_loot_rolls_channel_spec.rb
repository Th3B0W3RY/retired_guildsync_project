# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceLootRollsChannel, type: :channel do
  let(:owner) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:loot_roll) { create(:alliance_loot_roll, alliance: alliance, creator: owner) }
  let(:member_user) { create_alliance_paid_user!(:discord_auth) }

  before do
    create(:guild_member, guild: guild, user: member_user, role: :member, status: :active)
    create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active)
  end

  describe ".broadcast_update" do
    it "broadcasts alliance_loot_roll_update with entries and currently_open" do
      entry = loot_roll.alliance_loot_roll_entries.create!(user: member_user, roll_value: 88, display_name: "Member")

      expect(AllianceLootRollsChannel).to receive(:broadcast_to).with(
        loot_roll,
        hash_including(
          type:             "alliance_loot_roll_update",
          total_entries:    1,
          status:           "open",
          currently_open:   true,
          winner_id:        nil,
          entries:          array_including(
            hash_including(
              id:           entry.id,
              display_name: "Member",
              mask_name:    false,
              roll_value:   88,
              is_winner:    false,
              user_id:      member_user.id
            )
          )
        )
      )
      AllianceLootRollsChannel.broadcast_update(loot_roll)
    end

    it "sets mask_name and omits user_id when the roll is anonymous" do
      lr = create(:alliance_loot_roll, alliance: alliance, creator: owner, anonymous: true)
      lr.alliance_loot_roll_entries.create!(user: member_user, roll_value: 50, display_name: "Secret")

      expect(AllianceLootRollsChannel).to receive(:broadcast_to) do |_r, msg|
        expect(msg[:entries].first[:mask_name]).to eq(true)
        expect(msg[:entries].first).not_to have_key(:user_id)
      end
      AllianceLootRollsChannel.broadcast_update(lr)
    end
  end

  it "confirms subscription for an active alliance member" do
    stub_connection(current_user: member_user)
    subscribe(alliance_loot_roll_id: loot_roll.id)
    expect(subscription).to be_confirmed
  end

  it "rejects when the user is not an alliance member" do
    stub_connection(current_user: create(:user))
    subscribe(alliance_loot_roll_id: loot_roll.id)
    expect(subscription).to be_rejected
  end

  it "rejects when alliance_loot_roll_id is zero" do
    stub_connection(current_user: member_user)
    subscribe(alliance_loot_roll_id: 0)
    expect(subscription).to be_rejected
  end

  it "rejects when the loot roll does not exist" do
    stub_connection(current_user: member_user)
    subscribe(alliance_loot_roll_id: 999_999_999)
    expect(subscription).to be_rejected
  end
end
