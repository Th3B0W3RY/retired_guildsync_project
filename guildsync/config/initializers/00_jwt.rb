# frozen_string_literal: true

# Named 00_jwt.rb so this runs before devise_jwt.rb (alphabetical initializer order).
# Warden::JWTAuth decodes Bearer tokens using the configured secret; if JWT_SECRET is not a
# String (e.g. mis-typed credentials as a Hash), ruby-jwt raises and clients see
# "HMAC key expected to be a String".

raw_creds = Rails.application.credentials.jwt_secret
raw_creds = nil if raw_creds.is_a?(Hash) || raw_creds.is_a?(Array)
from_credentials = raw_creds.nil? ? nil : raw_creds.to_s.strip.presence
from_env = ENV["JWT_SECRET"].to_s.strip.presence
explicit = from_credentials || from_env
# Reject placeholder / weak explicit values; fall through to secret_key_base.
explicit = nil if explicit == "secret"

# Use SECRET_KEY_BASE when JWT_SECRET / credentials are unset (same pattern as Devise fallbacks).
# Previously we raised in production before this fallback, which broke first deploy with only SECRET_KEY_BASE.
jwt_secret = explicit.presence || Rails.application.secret_key_base.to_s
jwt_secret = jwt_secret.to_s

if Rails.env.production? && (jwt_secret.blank? || jwt_secret == "secret")
  raise "JWT secret must be set to a secure value in production (set SECRET_KEY_BASE and/or JWT_SECRET, or credentials.jwt_secret as a string)"
end

raise "JWT secret resolved to an empty value" if jwt_secret.blank?

JWT_SECRET = jwt_secret.freeze
