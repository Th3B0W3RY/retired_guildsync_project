# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildMemberWarningStatus, type: :model do
  describe "#apply_warning!" do
    it "increments warning count and bans at three warnings" do
      status = create(:guild_member_warning_status, warning_count: 2, state: :warned)
      issuer = create(:user)

      status.apply_warning!(reason: "Final warning", issuer: issuer)

      expect(status.warning_count).to eq(3)
      expect(status).to be_banned
      expect(status.last_warning_reason).to eq("Final warning")
      expect(status.warned_by).to eq(issuer)
    end
  end

  describe "#move_to_state!" do
    it "sets count to zero for no_warnings" do
      status = create(:guild_member_warning_status, warning_count: 2, state: :warned)

      status.move_to_state!("no_warnings")

      expect(status.warning_count).to eq(0)
      expect(status).to be_no_warnings
    end

    it "sets count to three for banned" do
      status = create(:guild_member_warning_status, warning_count: 1, state: :warned)

      status.move_to_state!("banned")

      expect(status.warning_count).to eq(3)
      expect(status).to be_banned
    end
  end
end
