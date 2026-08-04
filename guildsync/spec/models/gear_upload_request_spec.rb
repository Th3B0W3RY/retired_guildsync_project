# frozen_string_literal: true

require "rails_helper"

RSpec.describe GearUploadRequest, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let(:target_user) { create(:user) }

  def build_request(requester:)
    build(:gear_upload_request, guild: guild, requester: requester, target_user: target_user)
  end

  describe "validations" do
    it "is valid when the requester is the guild owner" do
      expect(build_request(requester: owner)).to be_valid
    end

    it "is valid when the requester is an active guild admin" do
      officer = create(:user)
      create(:guild_member, guild: guild, user: officer, role: :admin, status: :active)
      expect(build_request(requester: officer)).to be_valid
    end

    it "is valid when the requester is an active guild moderator" do
      mod = create(:user)
      create(:guild_member, guild: guild, user: mod, role: :moderator, status: :active)
      expect(build_request(requester: mod)).to be_valid
    end

    it "rejects a plain member without custom gear-request role mapping" do
      member = create(:user)
      create(:guild_member, guild: guild, user: member, role: :member, status: :active)
      req = build_request(requester: member)
      expect(req).not_to be_valid
      expect(req.errors.details[:requester].map { |h| h[:error] }).to include(:no_permission)
    end

    it "rejects a member whose Discord role matches permission_role_1_id but role_1 flag is off" do
      guild.update!(permission_role_1_id: "role-gear", role_1_can_manage_gear_requests: false)
      member = create(:user)
      create(:guild_member, guild: guild, user: member, role: :member, status: :active, discord_role_id: "role-gear")
      expect(build_request(requester: member)).not_to be_valid
    end

    it "allows a member when permission_role_1_id matches and role_1_can_manage_gear_requests is true" do
      guild.update!(permission_role_1_id: "role-gear", role_1_can_manage_gear_requests: true)
      member = create(:user)
      create(:guild_member, guild: guild, user: member, role: :member, status: :active, discord_role_id: "role-gear")
      expect(build_request(requester: member)).to be_valid
    end

    it "allows a member when permission_role_3 matches and role_3_can_manage_gear_requests is true" do
      guild.update!(
        permission_role_3_id: "role-three",
        role_3_can_manage_gear_requests: true
      )
      member = create(:user)
      create(:guild_member, guild: guild, user: member, role: :member, status: :active, discord_role_id: "role-three")
      expect(build_request(requester: member)).to be_valid
    end

    it "treats inactive membership as no permission for non-owners" do
      member = create(:user)
      create(:guild_member, guild: guild, user: member, role: :admin, status: :inactive)
      expect(build_request(requester: member)).not_to be_valid
    end
  end

  describe ".pending_for_user" do
    it "returns only pending rows for that guild and target user" do
      requester = owner
      pending = create(:gear_upload_request, guild: guild, requester: requester, target_user: target_user, status: :pending)
      create(:gear_upload_request, :completed, guild: guild, requester: requester, target_user: target_user)
      other = create(:user)
      create(:gear_upload_request, guild: guild, requester: requester, target_user: other, status: :pending)

      expect(described_class.pending_for_user(guild, target_user)).to contain_exactly(pending)
    end
  end

  describe "#mark_completed!" do
    it "sets status to completed and completed_at" do
      req = create(:gear_upload_request, guild: guild, requester: owner, target_user: target_user, status: :pending)
      freeze_time do
        req.mark_completed!
        expect(req.reload).to be_completed
        expect(req.completed_at).to eq(Time.current)
      end
    end
  end
end
