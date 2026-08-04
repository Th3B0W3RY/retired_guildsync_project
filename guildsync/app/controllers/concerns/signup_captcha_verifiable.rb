# frozen_string_literal: true

module SignupCaptchaVerifiable
  extend ActiveSupport::Concern

  private

  def turnstile_response_param
    params["cf-turnstile-response"].presence || params[:cf_turnstile_response].presence
  end

  def signup_turnstile_result
    TurnstileVerificationService.verify(
      response_token: turnstile_response_param,
      remote_ip: request.remote_ip
    )
  end
end
