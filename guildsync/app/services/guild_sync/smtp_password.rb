# frozen_string_literal: true

module GuildSync
  # Resolves the Resend (or other) SMTP password for production Action Mailer.
  # Blank or whitespace-only values are treated as missing so deploy/migrate fails fast.
  class SmtpPassword
    MISSING_MESSAGE = "SMTP_PASSWORD must be set in production (use your Resend API key for SMTP)."

    def self.require_for_production!
      pwd = ENV.fetch("SMTP_PASSWORD", "").to_s.strip
      raise ArgumentError, MISSING_MESSAGE if pwd.empty?

      pwd
    end
  end
end
