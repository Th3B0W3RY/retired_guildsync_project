# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Password reset instructions (email)", type: :request do
  include ActiveJob::TestHelper

  describe "POST /password" do
    it "sends Devise reset instructions with correct host in link (test delivery)" do
      user = create(:user, email: "reset-me@example.com", skip_free_plan_subscription: true)

      expect do
        post password_path, params: { user: { email: user.email } }
      end.to have_enqueued_job(ActionMailer::MailDeliveryJob)

      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to eq(I18n.t("passwords.create.instructions_sent"))

      perform_enqueued_jobs

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ Devise.mailer_sender ])

      body = mail.body.encoded
      expect(body).to include("http://example.com/")
      expect(body).not_to include("localhost")
      expect(body).to match(/password/i)
    end
  end
end
