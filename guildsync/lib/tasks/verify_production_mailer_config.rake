# frozen_string_literal: true

# Ensures production loads remote SMTP (Resend) from ENV — same variables systemd uses for
# Puma and Sidekiq. Run after deploy: bundle exec rake guildsync:verify_production_mailer_config
namespace :guildsync do
  desc "Verify production Action Mailer SMTP is configured for remote delivery (not implicit localhost:25)"
  task verify_production_mailer_config: :environment do
    unless Rails.env.production?
      puts "guildsync:verify_production_mailer_config — skip (RAILS_ENV is #{Rails.env})"
      next
    end

    GuildSync::ProductionActionMailerSmtp.apply_after_initialize!

    s = Rails.application.config.action_mailer.smtp_settings
    method = Rails.application.config.action_mailer.delivery_method
    puts "guildsync:verify_production_mailer_config — OK (smtp #{s[:address]}:#{s[:port]}, delivery_method: #{method.inspect})"
  end
end
