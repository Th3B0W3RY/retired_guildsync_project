# frozen_string_literal: true

class ConfirmationsController < Devise::ConfirmationsController
  layout "application"

  def create
    self.resource = resource_class.send_confirmation_instructions(resource_params)
    yield resource if block_given?

    if already_fully_confirmed_resend?(resource)
      redirect_to new_user_confirmation_path, alert: t("confirmations.create.already_registered")
      return
    end

    if successfully_sent?(resource)
      respond_with({}, location: after_resending_confirmation_instructions_path_for(resource_name))
    else
      respond_with(resource)
    end
  end

  private

  def already_fully_confirmed_resend?(resource)
    resource.persisted? && resource.errors.added?(:email, :already_confirmed)
  end

  protected

  def after_resending_confirmation_instructions_path_for(_resource_name)
    login_path
  end

  def after_confirmation_path_for(_resource_name, _resource)
    mfa_setup_path
  end
end
