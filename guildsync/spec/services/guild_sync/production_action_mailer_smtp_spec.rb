# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildSync::ProductionActionMailerSmtp do
  describe ".apply_after_initialize!" do
    it "does nothing when not in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
      prior = Rails.application.config.action_mailer.smtp_settings
      described_class.apply_after_initialize!
      expect(Rails.application.config.action_mailer.smtp_settings).to eq(prior)
    end

    it "assigns smtp_settings and does not raise for normal Resend-style config" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      old_pwd = ENV["SMTP_PASSWORD"]
      old_settings = Rails.application.config.action_mailer.smtp_settings.deep_dup
      old_base = ActionMailer::Base.smtp_settings.deep_dup
      ENV["SMTP_PASSWORD"] = "test-resend-key"
      ENV["SMTP_ADDRESS"] = "smtp.resend.com"
      ENV["SMTP_PORT"] = "587"
      ENV.delete("SMTP_ALLOW_LOCAL_MAILER")
      begin
        described_class.apply_after_initialize!
        expect(Rails.application.config.action_mailer.smtp_settings[:address]).to eq("smtp.resend.com")
        expect(Rails.application.config.action_mailer.smtp_settings[:port]).to eq(587)
        expect(ActionMailer::Base.smtp_settings[:address]).to eq("smtp.resend.com")
        expect(ActionMailer::Base.smtp_settings[:port]).to eq(587)
      ensure
        ENV["SMTP_PASSWORD"] = old_pwd
        ENV.delete("SMTP_ADDRESS")
        ENV.delete("SMTP_PORT")
        Rails.application.config.action_mailer.smtp_settings = old_settings
        ActionMailer::Base.smtp_settings = old_base
      end
    end

    it "raises when SMTP points at localhost:25 without SMTP_ALLOW_LOCAL_MAILER" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      old_pwd = ENV["SMTP_PASSWORD"]
      old_settings = Rails.application.config.action_mailer.smtp_settings.deep_dup
      old_base = ActionMailer::Base.smtp_settings.deep_dup
      ENV["SMTP_PASSWORD"] = "test-key"
      ENV["SMTP_ADDRESS"] = "localhost"
      ENV["SMTP_PORT"] = "25"
      ENV.delete("SMTP_ALLOW_LOCAL_MAILER")
      begin
        expect { described_class.apply_after_initialize! }.to raise_error(ArgumentError, /implicit local MTA/)
      ensure
        ENV["SMTP_PASSWORD"] = old_pwd
        ENV.delete("SMTP_ADDRESS")
        ENV.delete("SMTP_PORT")
        Rails.application.config.action_mailer.smtp_settings = old_settings
        ActionMailer::Base.smtp_settings = old_base
      end
    end

    it "allows localhost:25 when SMTP_ALLOW_LOCAL_MAILER=1" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      old_pwd = ENV["SMTP_PASSWORD"]
      old_allow = ENV["SMTP_ALLOW_LOCAL_MAILER"]
      old_settings = Rails.application.config.action_mailer.smtp_settings.deep_dup
      old_base = ActionMailer::Base.smtp_settings.deep_dup
      ENV["SMTP_PASSWORD"] = "test-key"
      ENV["SMTP_ADDRESS"] = "localhost"
      ENV["SMTP_PORT"] = "25"
      ENV["SMTP_ALLOW_LOCAL_MAILER"] = "1"
      begin
        expect { described_class.apply_after_initialize! }.not_to raise_error
        expect(Rails.application.config.action_mailer.smtp_settings[:address]).to eq("localhost")
        expect(ActionMailer::Base.smtp_settings[:address]).to eq("localhost")
      ensure
        ENV["SMTP_PASSWORD"] = old_pwd
        ENV.delete("SMTP_ADDRESS")
        ENV.delete("SMTP_PORT")
        if old_allow
          ENV["SMTP_ALLOW_LOCAL_MAILER"] = old_allow
        else
          ENV.delete("SMTP_ALLOW_LOCAL_MAILER")
        end
        Rails.application.config.action_mailer.smtp_settings = old_settings
        ActionMailer::Base.smtp_settings = old_base
      end
    end
  end
end
