# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupCode, type: :model do
  let(:user) { create(:user) }

  describe "BackupCodeGenerator" do
    it "loads bcrypt directly for backup-code digests" do
      output = IO.popen(
        [ Gem.ruby, "-rbundler/setup", "-e", "load 'app/services/backup_code_generator.rb'; puts defined?(BCrypt)" ],
        chdir: Rails.root.to_s,
        err: %i[ child out ],
        &:read
      )

      expect(output).to include("constant")
    end

    it "generates one code of 24 characters" do
      result = BackupCodeGenerator.generate_for_user(user)
      expect(result[:codes].size).to eq(1)
      expect(result[:codes].first.gsub("-", "").length).to eq(24)
    end

    it "returns file content for the generated code" do
      result = BackupCodeGenerator.generate_for_user(user)
      expect(result[:file_content]).to include("GUILDSYNC BACKUP CODE")
      expect(result[:file_content]).to include(user.email)
      expect(result[:file_content]).to include(result[:codes].first)
    end

    it "invalidates old codes when generating new ones" do
      BackupCodeGenerator.generate_for_user(user)
      first_count = user.backup_codes.count
      BackupCodeGenerator.generate_for_user(user)
      expect(user.backup_codes.count).to eq(2)
      expect(user.backup_codes.active.count).to eq(1)
      expect(user.backup_codes.where(active: false).count).to eq(1)
    end
  end

  describe ".valid_for_user?" do
    it "accepts correct backup code and marks it used" do
      result = BackupCodeGenerator.generate_for_user(user)
      raw_code = result[:codes].first.gsub("-", "")
      expect(BackupCode.valid_for_user?(user, raw_code)).to be true
      expect(BackupCode.valid_for_user?(user, raw_code)).to be false
    end

    it "accepts code with dashes" do
      result = BackupCodeGenerator.generate_for_user(user)
      code_with_dashes = result[:codes].first
      expect(BackupCode.valid_for_user?(user, code_with_dashes)).to be true
    end

    it "rejects wrong code" do
      BackupCodeGenerator.generate_for_user(user)
      expect(BackupCode.valid_for_user?(user, "WRONGCODE123456789012345")).to be false
    end

    it "rejects code for different user" do
      other_user = create(:user)
      result = BackupCodeGenerator.generate_for_user(user)
      raw_code = result[:codes].first.gsub("-", "")
      expect(BackupCode.valid_for_user?(other_user, raw_code)).to be false
    end

    it "creates a usage log when request metadata is provided" do
      result = BackupCodeGenerator.generate_for_user(user)
      raw_code = result[:codes].first.gsub("-", "")
      req = instance_double(ActionDispatch::Request, remote_ip: "203.0.113.1", user_agent: "RSpec")
      expect {
        BackupCode.valid_for_user?(user, raw_code, request: req)
      }.to change(BackupCodeUsageLog, :count).by(1)
      log = BackupCodeUsageLog.order(:id).last
      expect(log.user_id).to eq(user.id)
      expect(log.ip_address).to eq("203.0.113.1")
      expect(log.user_agent).to eq("RSpec")
    end
  end
end
