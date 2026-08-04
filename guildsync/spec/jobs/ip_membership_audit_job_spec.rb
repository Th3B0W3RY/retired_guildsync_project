# frozen_string_literal: true

require "rails_helper"

RSpec.describe IpMembershipAuditJob, type: :job do
  describe "#perform" do
    it "audits a single user when user_id is provided" do
      user = create(:user)
      service = instance_double(IpMembershipEnforcementService)
      allow(IpMembershipEnforcementService).to receive(:new).and_return(service)
      allow(service).to receive(:audit_user!)

      described_class.new.perform(user.id)

      expect(service).to have_received(:audit_user!).with(user)
    end

    it "runs full audit when no user_id is provided" do
      service = instance_double(IpMembershipEnforcementService)
      allow(IpMembershipEnforcementService).to receive(:new).and_return(service)
      allow(service).to receive(:audit_all_recent!)

      described_class.new.perform

      expect(service).to have_received(:audit_all_recent!)
    end
  end
end
