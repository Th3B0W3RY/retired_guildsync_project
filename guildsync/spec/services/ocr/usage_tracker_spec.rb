# frozen_string_literal: true

# OCR usage tracking only. NO external API calls (no Azure, no OCR engines). No real OCR requests or credits.
require "rails_helper"

RSpec.describe Ocr::UsageTracker, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, ocr_billing_plan: "upgraded", ocr_requests_used_this_period: 0, ocr_last_reset_at: Time.current.beginning_of_month) }

  def mock_request(ip: "127.0.0.1", ua: "Spec")
    double(remote_ip: ip, user_agent: ua)
  end

  describe ".check" do
    it "returns :ok when under limit" do
      status, err = described_class.check(user: user, amount: 1)
      expect(status).to eq(:ok)
      expect(err).to be_nil
    end

    it "returns :blocked when hard locked" do
      user.update!(ocr_hard_locked: true)
      status, err = described_class.check(user: user.reload, amount: 1)
      expect(status).to eq(:blocked)
      expect(err).to be_a(described_class::Blocked)
      expect(err.code).to eq(:hard_locked)
    end

    it "returns :blocked when at upgraded hard stop (4900 uses, limit 4900)" do
      user.update!(ocr_billing_plan: "upgraded", ocr_requests_used_this_period: 4900)
      status, err = described_class.check(user: user.reload, amount: 1)
      expect(status).to eq(:blocked)
      expect(err.code).to eq(:limit_reached)
    end

    it "allows ocr_unlocked to bypass limit" do
      user.update!(ocr_unlocked: true, ocr_requests_used_this_period: 9999)
      status, err = described_class.check(user: user.reload, amount: 1)
      expect(status).to eq(:ok)
      expect(err).to be_nil
    end
  end

  describe "trial plan hard stop (PLAN_LIMITS: 3/mo, buffer 0 → block when used >= 3)" do
    it "allows three successful increments then denies on the next check with OcrDenial" do
      trial_user = create(:user, ocr_billing_plan: "trial", ocr_requests_used_this_period: 0)
      3.times do
        expect(described_class.check(user: trial_user, amount: 1)).to eq([ :ok, nil ])
        described_class.increment_after_success!(user: trial_user, amount: 1)
        trial_user.reload
      end
      expect(trial_user.ocr_requests_used_this_period).to eq(3)
      expect { described_class.check(user: trial_user, amount: 1) }.to change(OcrDenial, :count).by(1)
      status, err = described_class.check(user: trial_user, amount: 1)
      expect(status).to eq(:blocked)
      expect(err.code).to eq(:limit_reached)
      denial = OcrDenial.last
      expect(denial.reason).to eq("hard_stop_reached")
      expect(denial.current_usage).to eq(3)
      expect(denial.limit).to eq(3)
      expect(denial.hard_stop).to eq(3)
    end
  end

  describe ".check_and_increment!" do
    it "increments usage and creates OcrRequest when check passes" do
      expect { described_class.check_and_increment!(user: user, amount: 1) }
        .to change { user.reload.ocr_requests_used_this_period }.by(1)
        .and change(OcrRequest, :count).by(1)
    end

    it "raises Blocked when at upgraded hard stop" do
      user.update!(ocr_requests_used_this_period: 4900)
      expect { described_class.check_and_increment!(user: user.reload, amount: 1) }.to raise_error(Ocr::UsageTracker::Blocked)
    end
  end

  describe ".increment_after_success!" do
    it "creates OcrRequest and increments user" do
      expect { described_class.increment_after_success!(user: user, amount: 1) }
        .to change { user.reload.ocr_requests_used_this_period }.by(1)
        .and change(OcrRequest, :count).by(1)
    end

    it "stores ip and user_agent when request is passed" do
      described_class.increment_after_success!(user: user, amount: 1, request: mock_request(ip: "192.168.1.1", ua: "Mozilla/5.0"))
      req = OcrRequest.last
      expect(req.ip_address).to eq("192.168.1.1")
      expect(req.user_agent).to eq("Mozilla/5.0")
    end

    it "sets initiated_by_id when initiator differs from billed user" do
      billing = user
      initiator = create(:user, ocr_billing_plan: "basic", ocr_requests_used_this_period: 0)
      described_class.increment_after_success!(user: billing, amount: 1, initiated_by: initiator)
      expect(OcrRequest.last).to have_attributes(user_id: billing.id, initiated_by_id: initiator.id)
    end

    it "stores nil initiated_by_id when initiator is the billed user" do
      described_class.increment_after_success!(user: user, amount: 1, initiated_by: user)
      expect(OcrRequest.last.initiated_by_id).to be_nil
    end

    it "stores nil initiated_by_id when initiated_by omitted" do
      described_class.increment_after_success!(user: user, amount: 1)
      expect(OcrRequest.last.initiated_by_id).to be_nil
    end
  end

  describe ".check_and_increment! initiated_by" do
    it "persists initiated_by_id when initiator differs from billed user" do
      billing = user
      initiator = create(:user, ocr_billing_plan: "basic", ocr_requests_used_this_period: 0)
      described_class.check_and_increment!(user: billing, amount: 1, initiated_by: initiator)
      expect(OcrRequest.last).to have_attributes(user_id: billing.id, initiated_by_id: initiator.id)
    end
  end

  describe ".can_process?" do
    it "returns false when at upgraded hard stop" do
      user.update!(ocr_requests_used_this_period: 4900)
      expect(described_class.can_process?(user.reload)).to be false
    end

    it "returns false when access_restricted (hard locked)" do
      user.update!(ocr_hard_locked: true)
      expect(described_class.can_process?(user.reload)).to be false
    end

    it "returns true when under limit" do
      expect(described_class.can_process?(user)).to be true
    end
  end

  describe ".current_monthly_usage" do
    it "returns usage and uses cache" do
      allow(Rails.cache).to receive(:fetch).and_call_original
      described_class.current_monthly_usage(user)
      expect(Rails.cache).to have_received(:fetch).with(/ocr:usage:/, expires_in: 5.minutes)
    end
  end

  describe "monthly period reset (upgraded)" do
    it "zeros period usage when ocr_last_reset_at is before the current month, then increments" do
      travel_to Time.zone.parse("2026-04-10 12:00:00") do
        u = create(:user,
          ocr_billing_plan: "upgraded",
          ocr_requests_used_this_period: 100,
          ocr_last_reset_at: Time.zone.parse("2026-03-05"))
        expect { described_class.check_and_increment!(user: u, amount: 1) }
          .to change { u.reload.ocr_requests_used_this_period }.from(100).to(1)
        expect(u.ocr_last_reset_at).to eq(Time.zone.parse("2026-04-01").beginning_of_day)
      end
    end
  end

  describe "IP abuse detection" do
    it "blocks when IP has excessive requests across accounts in 24h" do
      ip = "10.0.0.99"
      other_user = create(:user, ocr_billing_plan: "upgraded", ocr_requests_used_this_period: 0)
      # Create 1000 OcrRequests from this IP (no need to call real OCR)
      1000.times do
        OcrRequest.create!(user: other_user, ip_address: ip, created_at: Time.current)
      end
      new_user = create(:user, ocr_billing_plan: "basic", ocr_requests_used_this_period: 0)
      status, err = described_class.check(user: new_user, amount: 1, request: mock_request(ip: ip))
      expect(status).to eq(:blocked)
      expect(err.code).to eq(:ip_abuse)
      expect(AbuseFlag.for_target("IP", ip).exists?).to be true
    end
  end

  describe "rapid requests abuse flag" do
    it "creates AbuseFlag when user has >50 OCR requests in 1 minute" do
      u = create(:user, ocr_billing_plan: "basic", ocr_requests_used_this_period: 0)
      51.times { OcrRequest.create!(user: u, created_at: Time.current) }
      expect(AbuseFlag.where(target_type: "User", target_value: u.id.to_s).where("reason LIKE ?", "%Rapid OCR%").exists?).to be true
    end

    it "flags the initiator when rows bill a different user but initiated_by is set" do
      billing = create(:user, ocr_billing_plan: "upgraded", ocr_requests_used_this_period: 0, ocr_last_reset_at: Time.current.beginning_of_month)
      member = create(:user, ocr_billing_plan: "basic", ocr_requests_used_this_period: 0)
      51.times { OcrRequest.create!(user: billing, initiated_by: member, created_at: Time.current) }
      expect(AbuseFlag.where(target_type: "User", target_value: member.id.to_s).where("reason LIKE ?", "%Rapid OCR%").exists?).to be true
    end
  end

  # No OCR engine or Azure is invoked in any of these tests.
end
