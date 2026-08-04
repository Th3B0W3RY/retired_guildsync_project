# frozen_string_literal: true

# Secrets at rest: Discord OAuth tokens, per-guild bot tokens, MFA seeds (see encrypts on models).
# Generate keys: bundle exec rails db:encryption:init
# Then merge YAML into credentials (per environment) or set ENV on the host:
#   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#   ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
creds = Rails.application.credentials[:active_record_encryption]
creds = creds.is_a?(Hash) ? creds.symbolize_keys : {}

pk = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || creds[:primary_key]&.to_s&.presence
dk = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || creds[:deterministic_key]&.to_s&.presence
salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || creds[:key_derivation_salt]&.to_s&.presence

if pk.blank? || dk.blank? || salt.blank?
  if Rails.env.production?
    raise "Active Record encryption keys missing. " \
          "Run: bin/rails db:encryption:init and add credentials, or set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, " \
          "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY, ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT."
  elsif Rails.env.test?
    pk                   = "T" * 32
    dk                   = "U" * 32
    salt                 = "V" * 32
  else
    base = Rails.application.secret_key_base
    pk = Digest::SHA256.hexdigest("#{base}:guildsync_ar_primary")[0, 32]
    dk = Digest::SHA256.hexdigest("#{base}:guildsync_ar_deterministic")[0, 32]
    salt = Digest::SHA256.hexdigest("#{base}:guildsync_ar_salt")[0, 32]
  end
end

Rails.application.config.active_record.encryption.primary_key = pk
Rails.application.config.active_record.encryption.deterministic_key = dk
Rails.application.config.active_record.encryption.key_derivation_salt = salt
Rails.application.config.active_record.encryption.support_unencrypted_data = true
