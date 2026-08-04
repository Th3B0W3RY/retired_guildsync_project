# frozen_string_literal: true

module GuildSync
  # Applies Action Mailer SMTP settings in production and fails fast if configuration
  # would fall back to an implicit local MTA (localhost:25), which Sidekiq/Rails default
  # behavior can use when smtp_settings were never applied.
  module ProductionActionMailerSmtp
    class << self
      def apply_after_initialize!
        return unless Rails.env.production?

        settings = build_smtp_settings
        Rails.application.config.action_mailer.smtp_settings = settings
        assert_configured_for_remote_smtp!(settings)
        # Mail delivery reads ActionMailer::Base.smtp_settings; assigning only config.* leaves Base on
        # localhost:25, so Sidekiq MailDeliveryJob hits ECONNREFUSED.
        ActionMailer::Base.smtp_settings = settings.dup
      end

      def build_smtp_settings
        {
          address: ENV.fetch("SMTP_ADDRESS", "smtp.resend.com"),
          port: Integer(ENV.fetch("SMTP_PORT", "587")),
          user_name: ENV.fetch("SMTP_USERNAME", "resend"),
          password: GuildSync::SmtpPassword.require_for_production!,
          domain: ENV.fetch("SMTP_DOMAIN", "guild-sync.net"),
          authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
          enable_starttls_auto: ENV.fetch("SMTP_ENABLE_STARTTLS_AUTO", "true") == "true",
          open_timeout: Integer(ENV.fetch("SMTP_OPEN_TIMEOUT", "5")),
          read_timeout: Integer(ENV.fetch("SMTP_READ_TIMEOUT", "5"))
        }
      end

      def assert_configured_for_remote_smtp!(settings)
        return if ENV["SMTP_ALLOW_LOCAL_MAILER"] == "1"

        addr = settings[:address].to_s.strip.downcase
        port = Integer(settings[:port])

        if addr.blank?
          raise ArgumentError, "SMTP_ADDRESS resolved blank after production Action Mailer configuration."
        end

        loopback_hosts = %w[localhost 127.0.0.1 ::1].freeze
        if loopback_hosts.include?(addr) && port == 25
          raise ArgumentError,
            "Action Mailer SMTP points to #{addr}:#{port} (implicit local MTA). " \
            "Configure SMTP_ADDRESS and SMTP_PORT for your provider (e.g. smtp.resend.com / 587), " \
            "ensure SMTP_PASSWORD is set in the same EnvironmentFile as Sidekiq, and restart web + Sidekiq. " \
            "If you truly use a local MTA on port 25, set SMTP_ALLOW_LOCAL_MAILER=1."
        end
      end
    end
  end
end
