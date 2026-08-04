# frozen_string_literal: true

# Resolve SMTP credentials after the application is fully initialized so Zeitwerk can
# autoload GuildSync::SmtpPassword / GuildSync::ProductionActionMailerSmtp (initializers
# alone still run too early for some app/services constants).
# See config/environments/production.rb (delivery_method / raise_delivery_errors only).
return unless Rails.env.production?

Rails.application.config.after_initialize do
  GuildSync::ProductionActionMailerSmtp.apply_after_initialize!
end
