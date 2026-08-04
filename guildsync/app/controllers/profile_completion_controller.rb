class ProfileCompletionController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :ensure_fully_authenticated
  skip_before_action :check_credentials_setup_required
  before_action :check_if_already_complete, only: [ :show ]

  def show
    @user = current_user
  end

  def update
    @user = current_user

    if @user.email.to_s.include?("@discord.guildsync.local")
      @user.skip_reconfirmation!
    end

    # Update user with new profile data
    if @user.update(profile_params)
      # Reload user to get fresh data from database
      @user.reload
      # Re-sign in the user after password update to maintain session
      # Use bypass_sign_in to avoid password validation issues
      bypass_sign_in(@user)
      # Store user ID in session as backup (in case Warden session isn't preserved)
      session[:user_id] = @user.id
      # Set MFA verified flag for Discord users
      session[:mfa_verified] = true
      session[:mfa_verified_at] = Time.current.to_i
      # Ensure session is saved before redirect
      session.save if session.respond_to?(:save)
      # Redirect to MFA setup page
      redirect_to mfa_setup_path, notice: I18n.t("profile_completion.update.success")
    else
      # Show validation errors
      errors = @user.errors.full_messages
      Rails.logger.error "Profile completion failed: #{errors.join(', ')}"
      flash.now[:alert] = errors.join(", ")
      render :show, status: :unprocessable_entity
    end
  end

  private

  def check_if_already_complete
    return unless profile_complete?(current_user)

    redirect_to account_settings_path
  end

  def profile_complete?(user)
    user.email.present? &&
    user.username.present? &&
    user.encrypted_password.present? &&
    !user.email.include?("@discord.guildsync.local")
  end

  def profile_params
    params.require(:user).permit(:email, :username, :password, :password_confirmation)
  end
end
