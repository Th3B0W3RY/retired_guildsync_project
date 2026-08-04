class SettingsController < ApplicationController
  before_action :authenticate_user!, except: [ :release_notes ]
  before_action :assign_profile_email_state, only: [ :profile, :update_profile_username, :request_profile_email_verification ]

  def account
    @backup_codes = current_user.backup_codes.order(generated_at: :desc)
    @account_deletion_feature = AccountDeletion.feature_enabled?
    @account_deletion_eligibility = AccountDeletion::EligibilityChecker.new(current_user).call if @account_deletion_feature
    @account_deletion_request = current_user.account_deletion_request if @account_deletion_feature
  end

  def profile
    # Profile settings page (username, avatar, etc.)
  end

  def update_profile_username
    username_param = params.require(:user).permit(:username)[:username].to_s.strip
    if current_user.update(username: username_param)
      log_security_event(
        event: "profile.username_updated",
        status: "success",
        metadata: { username: current_user.username }
      )
      redirect_to profile_settings_path, notice: t("settings.profile.username.updated_notice")
    else
      flash.now[:alert] = current_user.errors.full_messages.to_sentence.presence ||
        t("settings.profile.username.update_failed")
      render :profile, status: :unprocessable_entity
    end
  end

  def request_profile_email_verification
    email = SignupEmailVerification.normalize_email(params[:email])
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to profile_settings_path, alert: t("account_creation.invalid_email")
      return
    end

    if User.where.not(id: current_user.id).exists?(email: email)
      redirect_to profile_settings_path, alert: t("settings.profile.email.taken")
      return
    end

    # One pending row per user (DB partial unique index). Reuse the same record so
    # enqueued ActionMailer::MailDeliveryJob GlobalIDs stay valid if the user resends
    # before Sidekiq drains the queue (delete_all + new id caused deserialization errors).
    verification = SignupEmailVerification.unverified.find_or_initialize_by(user_id: current_user.id)
    verification.email = email
    unless verification.save
      redirect_to profile_settings_path, alert: verification.errors.full_messages.to_sentence
      return
    end

    raw = verification.issue!(ip_address: request.remote_ip)
    SignupMailer.verify_profile_email(verification, raw).deliver_later

    log_security_event(
      event: "profile.email_verification_requested",
      status: "success",
      metadata: { email_domain: email.split("@").last }
    )

    redirect_to profile_settings_path, notice: t("settings.profile.email.verification_sent_notice")
  end

  def release_notes
    redirect_to_trusted_site_setting_url(SiteSetting.release_notes_url, fallback: root_path)
  end

  def update_locale
    locale = params[:preferred_locale].presence

    if locale.nil? || I18n.available_locales.map(&:to_s).include?(locale)
      current_user.update!(preferred_locale: locale)
      # Drop stale header/session locale so "Default" and explicit picks are not overridden next request
      session.delete(:locale)
      # Apply immediately (match ApplicationController: signed-in + no preference => default, not Accept-Language)
      I18n.locale = locale&.to_sym || I18n.default_locale
      redirect_back fallback_location: account_settings_path, notice: t('settings.account.language.updated')
    else
      redirect_back fallback_location: account_settings_path, alert: t('settings.account.language.invalid')
    end
  end

  private

  def assign_profile_email_state
    @pending_email_verification = SignupEmailVerification.unverified.find_by(user_id: current_user.id)
    @requires_real_email = !current_user.verified_real_email?
  end
end
