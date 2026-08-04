# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserRestoration::Registry do
  describe ".scope_for" do
    it "includes alliances where the user is leader_user_id even when they own no guilds" do
      leader = create(:user)
      other_owner = create(:user)
      guild = create(:guild, owner: other_owner)
      alliance = create(:alliance, leader_guild: guild, leader_user: leader)

      expect(described_class.owned_guild_ids(leader)).to be_empty

      scope = described_class.scope_for(Alliance, leader)
      expect(scope.where(id: alliance.id)).to exist
    end
  end
end
