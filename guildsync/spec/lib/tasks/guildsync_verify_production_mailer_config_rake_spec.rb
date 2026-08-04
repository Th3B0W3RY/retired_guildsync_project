# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "guildsync:verify_production_mailer_config rake task" do
  before do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  it "does not call ProductionActionMailerSmtp when not production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
    expect(GuildSync::ProductionActionMailerSmtp).not_to receive(:apply_after_initialize!)
    Rake::Task["guildsync:verify_production_mailer_config"].reenable
    Rake::Task["guildsync:verify_production_mailer_config"].invoke
  end

  it "applies SMTP config when RAILS_ENV is production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    old_pwd = ENV["SMTP_PASSWORD"]
    old_addr = ENV["SMTP_ADDRESS"]
    old_port = ENV["SMTP_PORT"]
    old_settings = Rails.application.config.action_mailer.smtp_settings.deep_dup
    ENV["SMTP_PASSWORD"] = "test-resend-key"
    ENV["SMTP_ADDRESS"] = "smtp.resend.com"
    ENV["SMTP_PORT"] = "587"
    ENV.delete("SMTP_ALLOW_LOCAL_MAILER")

    Rake::Task["guildsync:verify_production_mailer_config"].reenable
    expect { Rake::Task["guildsync:verify_production_mailer_config"].invoke }.not_to raise_error
  ensure
    ENV["SMTP_PASSWORD"] = old_pwd
    if old_addr
      ENV["SMTP_ADDRESS"] = old_addr
    else
      ENV.delete("SMTP_ADDRESS")
    end
    if old_port
      ENV["SMTP_PORT"] = old_port
    else
      ENV.delete("SMTP_PORT")
    end
    Rails.application.config.action_mailer.smtp_settings = old_settings
  end
end
