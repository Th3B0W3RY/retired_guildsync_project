# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignupMailer, type: :mailer do
  describe "#verify_email" do
    it "renders professional verification copy and link" do
      verification = SignupEmailVerification.create!(email: "verify@example.com")
      token = verification.issue!(ip_address: "127.0.0.1")

      mail = described_class.verify_email(verification, token)

      expect(mail.to).to eq([ "verify@example.com" ])
      expect(mail.subject).to eq(I18n.t("account_creation.mailer.verify_email.subject"))
      expect(mail.body.encoded).to include("Welcome to GuildSync")
      expect(mail.body.encoded).to include("Verify Email Address")
      expect(mail.body.encoded).to include("#6366f1")
      expect(mail.body.encoded).to include("If you did not create a GuildSync account")
      expect(mail.body.encoded).to include(token)
      expect(mail.body.encoded).to include("- GuildSync Team")

      expected_url = Rails.application.routes.url_helpers.create_account_verify_url(token: token, host: "example.com")
      html = mail.html_part.decoded
      expect(html).to include(expected_url)
      expect(html.scan(expected_url).size).to be >= 2
      verify_hrefs = html.scan(/href="([^"]+)"/).flatten.select { |href| href.include?("/create_account/verify/") }
      expect(verify_hrefs).to eq([ expected_url, expected_url ])
      expect(html).to include('role="presentation"')
    end
  end

  describe "#verify_profile_email" do
    include ActiveJob::TestHelper

    before { clear_enqueued_jobs }
    it "links to profile email verification URL" do
      user = create(:user)
      verification = SignupEmailVerification.create!(user_id: user.id, email: "profile-verify@example.com")
      token = verification.issue!(ip_address: "127.0.0.1")

      mail = described_class.verify_profile_email(verification, token)

      expect(mail.to).to eq([ "profile-verify@example.com" ])
      expect(mail.subject).to eq(I18n.t("settings.profile.email.mailer.subject"))
      expect(mail.body.encoded).to include("You requested to verify this email address for your GuildSync profile")
      expect(mail.body.encoded).to include("Verify Email Address")
      expect(mail.body.encoded).to include("#6366f1")
      expect(mail.body.encoded).to include(token)
      expect(mail.body.encoded).to include("/profile/email/verify?token=")

      expected_url = Rails.application.routes.url_helpers.verify_profile_email_url(token: token, host: "example.com")
      html = mail.html_part.decoded
      expect(html).to include(expected_url)
      expect(html.scan(expected_url).size).to be >= 2
      verify_hrefs = html.scan(/href="([^"]+)"/).flatten.select { |href| href.include?("/profile/email/verify") }
      expect(verify_hrefs).to eq([ expected_url, expected_url ])
      expect(html).to include('role="presentation"')
    end

    it "deliver_later enqueues MailDeliveryJob with SignupMailer class name (not a typo)" do
      user = create(:user)
      verification = SignupEmailVerification.create!(user_id: user.id, email: "profile-verify@example.com")
      token = verification.issue!(ip_address: "127.0.0.1")

      described_class.verify_profile_email(verification, token).deliver_later

      mail_job = enqueued_jobs.find { |j| j[:job] == ActionMailer::MailDeliveryJob }
      expect(mail_job).to be_present
      expect(mail_job[:args].first).to eq("SignupMailer")
    end
  end
end
