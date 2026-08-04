# frozen_string_literal: true

class AccountMailer < ApplicationMailer
  def backup_code_regenerated(user, backup_code)
    @user = user
    @backup_code = backup_code

    mail(
      to: @user.email,
      subject: I18n.t("account_creation.mailer.backup_code_regenerated.subject")
    )
  end

  def deletion_code(user_id, code)
    @user = User.find(user_id)
    @code = code

    mail(
      to: @user.email,
      subject: I18n.t("account_deletion.mailer.deletion_code.subject")
    )
  end
end
