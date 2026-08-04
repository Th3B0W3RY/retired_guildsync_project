# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions#new email_login param", type: :request do
  # Rack::Test cookie jar has no .signed writer; match discord_auth_persistence_spec.
  def generate_signed_cookie(name, value)
    secret = Rails.application.key_generator.generate_key(
      Rails.application.config.action_dispatch.signed_cookie_salt
    )
    verifier = ActiveSupport::MessageVerifier.new(
      secret,
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )
    verifier.generate(value.to_json, purpose: "cookie.#{name}")
  end

  describe "GET /login" do
    it "returns 200 when email_login=1 even if discord_uid cookie would trigger silent Discord path" do
      conn = create(:user_discord_connection, refresh_token: "fake-refresh-token")
      get "/login"
      cookies[:discord_uid] = generate_signed_cookie(:discord_uid, conn.discord_user_id)

      get "/login", params: { email_login: "1" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email")
      expect(response).not_to redirect_to(%r{/auth/discord})
    end
  end
end
