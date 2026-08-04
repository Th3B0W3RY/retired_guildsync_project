# frozen_string_literal: true

Devise.setup do |config|
  config.jwt do |jwt|
    # Use the String from 00_jwt.rb (loaded first). A Proc is not resolved by
    # Warden::JWTAuth::TokenDecoder's dry-auto_inject wiring — JWT.decode would receive a Proc and raise
    # "HMAC key expected to be a String".
    jwt.secret = JWT_SECRET
    jwt.dispatch_requests = [
      [ "POST", %r{^/api/v1/auth/sign_in$} ],
      [ "POST", %r{^/api/v1/auth/sign_up$} ]
    ]
    jwt.revocation_requests = [
      [ "DELETE", %r{^/api/v1/auth/sign_out$} ]
    ]
    jwt.expiration_time = 1.day.to_i
  end
end
