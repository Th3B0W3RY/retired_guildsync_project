# frozen_string_literal: true

require "rails_helper"

RSpec.describe IpMembershipEnforcementService do
  describe "#check_before_guild_join!" do
    it "blocks joining when shared IP account is active in another guild" do
      guild_a = create(:guild)
      guild_b = create(:guild)
      user_one = create(:user, signup_ip: "203.0.113.10")
      user_two = create(:user, signup_ip: "203.0.113.11")
      create(:login_history, user: user_one, ip_address: "203.0.113.200")
      create(:login_history, user: user_two, ip_address: "203.0.113.200")
      create(:guild_member, user: user_two, guild: guild_a, status: :active)

      service = described_class.new

      expect {
        service.check_before_guild_join!(user: user_one, target_guild: guild_b)
      }.to raise_error(IpMembershipEnforcementService::ConflictError)
    end

    it "allows join when shared IP account is active in same guild" do
      guild = create(:guild)
      user_one = create(:user, signup_ip: "198.51.100.7")
      user_two = create(:user, signup_ip: "198.51.100.8")
      create(:login_history, user: user_one, ip_address: "198.51.100.200")
      create(:login_history, user: user_two, ip_address: "198.51.100.200")
      create(:guild_member, user: user_two, guild: guild, status: :active)

      service = described_class.new

      expect {
        service.check_before_guild_join!(user: user_one, target_guild: guild)
      }.not_to raise_error
    end
  end

  describe "#audit_user!" do
    it "creates active warnings on all conflict accounts" do
      guild_a = create(:guild)
      guild_b = create(:guild)
      user_one = create(:user, signup_ip: "192.0.2.3")
      user_two = create(:user, signup_ip: "192.0.2.4")
      create(:guild_member, user: user_one, guild: guild_a, status: :active)
      create(:guild_member, user: user_two, guild: guild_b, status: :active)
      create(:login_history, user: user_one, ip_address: "192.0.2.200")
      create(:login_history, user: user_two, ip_address: "192.0.2.200")

      service = described_class.new
      service.audit_user!(user_one)

      warning_one = UserComplianceWarning.find_by(user: user_one, warning_type: UserComplianceWarning::WARNING_TYPE_IP_CONFLICT)
      warning_two = UserComplianceWarning.find_by(user: user_two, warning_type: UserComplianceWarning::WARNING_TYPE_IP_CONFLICT)

      expect(warning_one).to be_present
      expect(warning_two).to be_present
      expect(warning_one.active).to be(true)
      expect(warning_two.active).to be(true)
    end
  end
end
