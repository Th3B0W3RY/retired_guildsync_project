# frozen_string_literal: true

module ApiHelpers
  # Helper method to generate JWT token for testing
  # Uses the exact same format as the auth controller
  def generate_jwt_token(user)
    require "jwt"
    require "securerandom"
    
    # Build payload with all required claims for Devise-JWT compatibility
    # - sub: user identifier (from jwt_subject method, which returns id)
    # - scp: scope as string (":user" -> "user")
    # - aud: audience (nil for tests, can be set via header in real requests)
    # - jti: JWT ID for token revocation support
    # - exp: expiration time
    # - user_id: kept for backward compatibility with our custom authentication
    payload = {
      'sub' => user.jwt_subject.to_s,  # Required by Devise-JWT
      'scp' => 'user',                  # Required by Devise-JWT (scope as string)
      'aud' => nil,                     # Required by Devise-JWT (can be nil)
      'jti' => SecureRandom.uuid,      # Required by Devise-JWT's TokenDecoder
      'exp' => 24.hours.from_now.to_i,  # Expiration time
      'user_id' => user.id              # Backward compatibility
    }

    # Use the exact same format as the auth controller
    JWT.encode(payload, JWT_SECRET, 'HS256')
  end

  # Helper to set Authorization header with JWT token
  # Includes Accept: application/json header to ensure JSON responses
  def auth_headers_with_token(user)
    {
      "Authorization" => "Bearer #{generate_jwt_token(user)}",
      "Accept" => "application/json"
    }
  end

  # Helper for making JSON API requests with authentication
  # Combines JWT token and JSON headers
  def json_api_headers(user)
    auth_headers_with_token(user)
  end
  
  # Helper to authenticate user for API requests using Devise test helpers
  # This bypasses JWT and uses session-based auth for tests
  def api_authenticate_user(user)
    # For API tests, we need to authenticate the user
    # Since the API uses JWT but tests might not work with JWT properly,
    # we'll use a workaround: sign in the user and set session
    sign_in user
    # Set MFA verification in session since API requires it
    session[:mfa_verified] = true
    session[:mfa_verified_at] = Time.current.to_i
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end

