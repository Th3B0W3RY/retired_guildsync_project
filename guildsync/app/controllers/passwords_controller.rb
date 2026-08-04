class PasswordsController < Devise::PasswordsController
  layout "application"

  # POST /password - Send password reset email
  def create
    self.resource = resource_class.send_reset_password_instructions(resource_params)
    yield resource if block_given?

    if successfully_sent?(resource)
      redirect_to login_path, notice: I18n.t("passwords.create.instructions_sent")
    else
      redirect_to new_password_path, alert: I18n.t("passwords.create.invalid_email")
    end
  end

  # GET /password/edit?reset_password_token=xxx - Reset password form
  def edit
    super
    @reset_password_token = params[:reset_password_token]
  end

  # PUT /password - Update password
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)
    yield resource if block_given?

    if resource.errors.empty?
      resource.after_database_authentication if Devise.sign_in_after_reset_password
      sign_in(resource) if Devise.sign_in_after_reset_password
      redirect_to dashboard_path, notice: I18n.t("passwords.update.success")
    else
      set_minimum_password_length
      @reset_password_token = params[:user][:reset_password_token]
      respond_with resource, status: :unprocessable_entity
    end
  end

  private

  def resource_params
    params.require(:user).permit(:email, :password, :password_confirmation, :reset_password_token)
  end
end
