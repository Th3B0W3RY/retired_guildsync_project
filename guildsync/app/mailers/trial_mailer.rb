class TrialMailer < ApplicationMailer
  default from: -> {
    ENV.fetch("BILLING_MAILER_FROM") { ENV.fetch("MAILER_FROM", "no-reply@guild-sync.net") }
  }

  # Sends a warning email a few days before a trial expires.
  def trial_expiring(subscription_id)
    @subscription = Subscription.find(subscription_id)
    @user = @subscription.user
    return if @user.email.blank?

    @days_remaining = ((@subscription.trial_ends_at - Time.current) / 1.day).ceil if @subscription.trial_ends_at

    locale = @user.preferred_locale.presence || I18n.default_locale
    I18n.with_locale(locale) do
      mail(
        to: @user.email,
        subject: I18n.t("mailers.trial_mailer.trial_expiring.subject")
      )
    end
  end
end
