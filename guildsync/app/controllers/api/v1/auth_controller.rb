module Api
  module V1
    class AuthController < ApplicationController
      include SignupCaptchaVerifiable

      skip_before_action :verify_authenticity_token
      skip_before_action :authenticate_user!, only: [ :sign_up, :sign_in, :me, :sign_out, :test_reset_password_token ]
      skip_before_action :require_mfa_if_enabled, only: [ :sign_up, :sign_in, :me, :sign_out, :test_reset_password_token ]
      skip_before_action :ensure_fully_authenticated, only: [ :sign_up, :sign_in, :me, :sign_out, :test_reset_password_token ]
      skip_before_action :validate_session, only: [ :sign_up, :sign_in, :test_reset_password_token ]
      skip_before_action :check_credentials_setup_required, only: [ :sign_up, :sign_in, :me, :sign_out, :test_reset_password_token ]

      # Force JSON format for API responses
      before_action :force_json_format

      # Custom authentication for protected endpoints (me, sign_out)
      before_action :authenticate_user_for_api!, only: [ :me, :sign_out ]

      rescue_from Warden::NotAuthenticated, with: :user_not_authenticated

      def sign_up
        unless signup_turnstile_result == :ok
          render json: { error: I18n.t("api.auth.captcha_invalid") }, status: :unprocessable_content
          return
        end

        user = User.new(sign_up_params)
        user.auth_method = :mfa
        user.signup_ip = request.remote_ip if user.respond_to?(:signup_ip=)

        # Check if skip_mfa_verification parameter is provided (before save, since we need to check the param)
        skip_mfa_flag = params.dig(:user, :skip_mfa_verification)
        skip_mfa_verification_requested = Rails.env.test? &&
          (skip_mfa_flag == true ||
           skip_mfa_flag == "true" ||
           skip_mfa_flag == 1 ||
           skip_mfa_flag == "1")
        test_confirm_email_requested = Rails.env.test? &&
          truthy_param?(params.dig(:user, :test_confirm_email))
        test_skip_mfa_auto_setup_requested = Rails.env.test? &&
          truthy_param?(params.dig(:user, :test_skip_mfa_auto_setup))

        if user.save
          # Log user creation via API (without exposing sensitive details)
          Rails.logger.warn "[API] New user created via API sign-up endpoint (User ID: #{user.id})"

          user.ensure_free_plan_subscription
          confirm_test_user_email!(user) if skip_mfa_verification_requested || test_confirm_email_requested

          unless user.active_for_authentication?
            render json: {
              message: I18n.t("api.auth.confirmation_required"),
              user: UserBlueprint.render_as_hash(user_for_private_api(user), view: :private)
            }, status: :created
            return
          end

          # In test environment, automatically set up MFA for users with auth_method: "mfa"
          if Rails.env.test? && !test_skip_mfa_auto_setup_requested && user.auth_method == "mfa" && user.otp_secret.present?
            require "rotp"
            totp = ROTP::TOTP.new(user.otp_secret)
            code = totp.now

            # Verify the code (which will succeed since we just generated it)
            if user.verify_totp(code)
              user.update!(
                mfa_enabled: true,
                mfa_verified: true
              )
              Rails.logger.debug "[API] Automatically enabled MFA for test user #{user.id}"
            end
          end

          # Store skip_mfa_verification flag if requested
          # This allows integration tests to opt-in to auto-verification (skip MFA verification step)
          # Uses in-memory hash in test environment (Rails.cache uses :null_store)
          if skip_mfa_verification_requested
            if Rails.env.test?
              User.skip_mfa_verification_flags[user.id] = true
            else
              Rails.cache.write("user_#{user.id}_skip_mfa_verification", true, expires_in: 5.minutes)
            end
          end

          render json: {
            message: I18n.t("api.auth.user_created"),
            user: UserBlueprint.render_as_hash(user_for_private_api(user), view: :private),
            token: generate_jwt_token(user)
          }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def sign_in
        user = User.find_by(email: sign_in_params[:email])
        if user && user.valid_password?(sign_in_params[:password])
          unless user.active_for_authentication?
            render json: { error: api_sign_in_inactive_error_message(user) }, status: :unauthorized
            return
          end

          render json: {
            message: I18n.t("api.auth.signed_in"),
            user: UserBlueprint.render_as_hash(user_for_private_api(user), view: :private),
            token: generate_jwt_token(user)
          }, status: :ok
        else
          render json: { error: I18n.t("api.auth.invalid_sign_in") }, status: :unauthorized
        end
      end

      def me
        # current_user is set by authenticate_user_for_api!
        if current_user.nil?
          render json: { error: I18n.t("api.auth.me_user_missing") }, status: :unauthorized
          return
        end

        begin
          render json: {
            user: UserBlueprint.render_as_hash(user_for_private_api(current_user), view: :private)
          }, status: :ok
        rescue => e
          Rails.logger.error "Error in me action: #{e.class.name}: #{e.message}"
          Rails.logger.error "Backtrace:\n#{e.backtrace.join("\n")}"
          render json: {
            error: I18n.t("api.auth.internal_error"),
            message: e.message,
            class: e.class.name,
            backtrace: Rails.env.test? ? e.backtrace.first(10) : nil
          }, status: :internal_server_error
        end
      end

      # Test-only: generate a real password reset token for a given email.
      # Gated on INTEGRATION_TESTS=1 or Rails.env.test? — never available in production.
      def test_reset_password_token
        unless Rails.env.test? || ENV["INTEGRATION_TESTS"] == "1"
          render json: { error: "Not available outside test environments" }, status: :forbidden
          return
        end

        user = User.find_by(email: params[:email])
        unless user
          render json: { error: "User not found" }, status: :not_found
          return
        end

        raw_token = user.send(:set_reset_password_token)
        render json: { token: raw_token }, status: :ok
      end

      def sign_out
        # JWT tokens are stateless, so we just return success
        # In a production app, you might want to blacklist tokens
        # current_user is set by authenticate_user_for_api!
        begin
          render json: { message: I18n.t("api.auth.signed_out") }, status: :ok
        rescue => e
          Rails.logger.error "Error in sign_out action: #{e.class.name}: #{e.message}"
          Rails.logger.error "Backtrace:\n#{e.backtrace.join("\n")}"
          render json: {
            error: I18n.t("api.auth.internal_error"),
            message: e.message,
            class: e.class.name,
            backtrace: Rails.env.test? ? e.backtrace.first(10) : nil
          }, status: :internal_server_error
        end
      end

      private

      def user_for_private_api(user)
        User.includes(current_subscription: :pricing_plan).find(user.id)
      end

      def force_json_format
        request.format = :json
      end

      def authenticate_user_for_api!
        # Try JWT token authentication first
        if authenticate_user_from_token!
          # Ensure current_user is set
          unless current_user
            render json: { error: I18n.t("api.auth.authentication_failed") }, status: :unauthorized
            return false
          end
          return true
        end

        # Fall back to session-based authentication
        unless user_signed_in?
          render json: { error: I18n.t("api.v1.authentication_required") }, status: :unauthorized
          return false
        end

        # Ensure current_user is set
        unless current_user
          render json: { error: I18n.t("api.auth.authentication_failed") }, status: :unauthorized
          return false
        end

        true
      end

      def extract_jwt_token
        auth_header = request.headers["Authorization"]
        return nil unless auth_header&.start_with?("Bearer ")

        auth_header.split(" ").last
      end

      def authenticate_user_from_token!
        token = extract_jwt_token
        return false unless token

        begin
          require "jwt"

          decode_options = {
            algorithm: "HS256",
            verify_jti: false
          }

          decoded_token = JWT.decode(token, JWT_SECRET, true, decode_options)
          payload = decoded_token[0]

          user_id = payload["user_id"] || payload["sub"]
          user = User.find_by(id: user_id)

          if user && user.active_for_authentication?
            # Set up Warden context for API authentication (stateless, no session)
            set_api_user_context(user)
            return true
          end
        rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidJtiError, ActiveRecord::RecordNotFound => e
          Rails.logger.debug "JWT authentication failed: #{e.message}"
          return false
        end

        false
      end

      # Sets up Warden user context for stateless API authentication
      # This makes current_user available without creating a session
      # Note: We use warden.set_user directly instead of Devise's sign_in helper because
      # our sign_in action method shadows the helper method
      def set_api_user_context(user)
        # Set user in Warden directly (ensures Warden context is set for stateless API requests)
        # This is equivalent to calling Devise's sign_in(user, store: false) but avoids the
        # method name conflict with our sign_in action method
        if respond_to?(:warden)
          warden.set_user(user, scope: :user, store: false)
        end

        # Explicitly set current_user to ensure it's available
        @current_user = user
      end

      def user_not_authenticated
        render json: { error: I18n.t("api.v1.authentication_required") }, status: :unauthorized
      end

      def api_sign_in_inactive_error_message(user)
        case user.inactive_message
        when :unconfirmed
          I18n.t("api.auth.unconfirmed_sign_in")
        when :archived
          I18n.t("api.auth.archived_sign_in")
        when :pending_registration
          I18n.t("api.auth.pending_registration_sign_in")
        else
          I18n.t("api.auth.invalid_sign_in")
        end
      end

      def truthy_param?(value)
        value == true || value == "true" || value == 1 || value == "1"
      end

      def confirm_test_user_email!(user)
        user.confirm
        return unless user.respond_to?(:signup_email_verified_at)
        return if user.signup_email_verified_at.present?

        user.update!(signup_email_verified_at: Time.current)
      end

      def sign_up_params
        params.require(:user).permit(:email, :password, :password_confirmation, :username)
      end

      def sign_in_params
        params.require(:user).permit(:email, :password)
      end

      def generate_jwt_token(user)
        # Generate JWT token compatible with Devise-JWT's expectations
        require "jwt"
        require "securerandom"

        # Get audience from request header (defaults to nil if not present)
        # This matches Devise-JWT's behavior
        aud = request.headers["JWT_AUD"]

        # Build payload with all required claims for Devise-JWT compatibility
        # - sub: user identifier (from jwt_subject method, which returns id)
        # - scp: scope as string (":user" -> "user")
        # - aud: audience from JWT_AUD header (can be nil)
        # - jti: JWT ID for token revocation support
        # - exp: expiration time
        # - user_id: kept for backward compatibility with our custom authentication
        payload = {
          "sub" => user.jwt_subject.to_s,  # Required by Devise-JWT
          "scp" => "user",                  # Required by Devise-JWT (scope as string)
          "aud" => aud,                     # Required by Devise-JWT (can be nil)
          "jti" => SecureRandom.uuid,      # Required by Devise-JWT's TokenDecoder
          "exp" => 24.hours.from_now.to_i,  # Expiration time
          "user_id" => user.id              # Backward compatibility
        }

        JWT.encode(payload, JWT_SECRET, "HS256")
      end
    end
  end
end
