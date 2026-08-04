# frozen_string_literal: true

require "rails_helper"

RSpec.describe TrialMailer, type: :mailer do
  include ActiveJob::TestHelper

  let(:user) { create(:user, email: "trial-user@example.com", skip_free_plan_subscription: true) }
  let(:subscription) do
    create(
      :subscription,
      user: user,
      status: :trialing,
      trial_ends_at: 2.days.from_now,
      trial_warning_sent_at: nil
    )
  end

  describe "#trial_expiring" do
    it "uses BILLING_MAILER_FROM when set" do
      old_b = ENV["BILLING_MAILER_FROM"]
      old_m = ENV["MAILER_FROM"]
      ENV["BILLING_MAILER_FROM"] = "billing-example@example.com"
      ENV.delete("MAILER_FROM")
      begin
        mail = described_class.trial_expiring(subscription.id)
        expect(mail.from).to eq([ "billing-example@example.com" ])
        expect(mail.subject).to eq(I18n.t("mailers.trial_mailer.trial_expiring.subject", locale: :en))
      ensure
        if old_b.nil?
          ENV.delete("BILLING_MAILER_FROM")
        else
          ENV["BILLING_MAILER_FROM"] = old_b
        end
        if old_m.nil?
          ENV.delete("MAILER_FROM")
        else
          ENV["MAILER_FROM"] = old_m
        end
      end
    end

    it "falls back to MAILER_FROM when BILLING_MAILER_FROM is unset" do
      old_b = ENV["BILLING_MAILER_FROM"]
      old_m = ENV["MAILER_FROM"]
      ENV.delete("BILLING_MAILER_FROM")
      ENV["MAILER_FROM"] = "fallback-from@example.com"
      begin
        mail = described_class.trial_expiring(subscription.id)
        expect(mail.from).to eq([ "fallback-from@example.com" ])
        expect(mail.subject).to eq(I18n.t("mailers.trial_mailer.trial_expiring.subject", locale: :en))
      ensure
        if old_b.nil?
          ENV.delete("BILLING_MAILER_FROM")
        else
          ENV["BILLING_MAILER_FROM"] = old_b
        end
        if old_m.nil?
          ENV.delete("MAILER_FROM")
        else
          ENV["MAILER_FROM"] = old_m
        end
      end
    end

    it "delivers via deliver_later without touching the network (test adapter)" do
      expect do
        perform_enqueued_jobs do
          described_class.trial_expiring(subscription.id).deliver_later
        end
      end.to change(ActionMailer::Base.deliveries, :size).by(1)

      delivered = ActionMailer::Base.deliveries.last
      expect(delivered.to).to eq([ "trial-user@example.com" ])
      expect(delivered.subject).to eq(I18n.t("mailers.trial_mailer.trial_expiring.subject", locale: :en))
    end

    it "uses the subscriber preferred_locale for the subject" do
      user.update!(preferred_locale: "ja")
      mail = described_class.trial_expiring(subscription.id)
      expect(mail.subject).to eq(I18n.t("mailers.trial_mailer.trial_expiring.subject", locale: :ja))
    end
  end
end
