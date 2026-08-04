# frozen_string_literal: true

class SignupMailer < ApplicationMailer
  def verify_email(verification, raw_token)
    @verification = verification
    @verify_url = create_account_verify_url(token: raw_token)

    mail(
      to: verification.email,
      subject: I18n.t("account_creation.mailer.verify_email.subject")
    )
  end

  def verify_profile_email(verification, raw_token)
    @verification = verification
    @verify_url = verify_profile_email_url(token: raw_token)

    mail(
      to: verification.email,
      subject: I18n.t("settings.profile.email.mailer.subject")
    )
  end
end
