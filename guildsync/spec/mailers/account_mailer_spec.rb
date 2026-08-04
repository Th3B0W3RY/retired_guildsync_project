# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountMailer, type: :mailer do
  describe "#backup_code_regenerated" do
    it "sends the regenerated backup code to the verified account email" do
      user = create(:user, email: "backup@example.com", signup_email_verified_at: Time.current)
      mail = described_class.backup_code_regenerated(user, "ABCD-EFGH-JKLM-NPQR-STUV-WXYZ")

      expect(mail.to).to eq([ "backup@example.com" ])
      expect(mail.subject).to eq(I18n.t("account_creation.mailer.backup_code_regenerated.subject"))
      expect(mail.body.encoded).to include("ABCD-EFGH-JKLM-NPQR-STUV-WXYZ")
      expect(mail.body.encoded).to include("- GuildSync Team")
    end
  end

  describe "#deletion_code" do
    it "sends only to the user email and includes the code (no extra token URLs)" do
      user = create(:user, username: "deleter", email: "deleter@example.com")
      mail = described_class.deletion_code(user.id, "A1B2C3D4")

      expect(mail.to).to eq([ "deleter@example.com" ])
      expect(mail.subject).to eq(I18n.t("account_deletion.mailer.deletion_code.subject"))
      body = mail.text_part&.decoded || mail.body.decoded
      expect(body).to include("A1B2C3D4")
      expect(body).not_to include("http")
      expect(body).to include("deleter")
    end
  end
end
