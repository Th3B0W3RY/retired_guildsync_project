# frozen_string_literal: true

require "rails_helper"

# Concrete mailer for spec only (no templates — uses explicit body).
class SpecPingMailer < ApplicationMailer
  def ping
    mail(to: "recipient@example.com", subject: "Ping", body: "body")
  end
end

RSpec.describe ApplicationMailer, type: :mailer do
  describe "default from" do
    it "uses MAILER_FROM when set" do
      old = ENV["MAILER_FROM"]
      ENV["MAILER_FROM"] = "branded-from@example.com"
      begin
        mail = SpecPingMailer.ping
        expect(mail.from).to eq([ "branded-from@example.com" ])
      ensure
        if old.nil?
          ENV.delete("MAILER_FROM")
        else
          ENV["MAILER_FROM"] = old
        end
      end
    end

    it "falls back to no-reply@guild-sync.net when MAILER_FROM is unset" do
      old = ENV["MAILER_FROM"]
      ENV.delete("MAILER_FROM")
      begin
        mail = SpecPingMailer.ping
        expect(mail.from).to eq([ "no-reply@guild-sync.net" ])
      ensure
        if old.nil?
          ENV.delete("MAILER_FROM")
        else
          ENV["MAILER_FROM"] = old
        end
      end
    end

    it "does not use from@example.com" do
      mail = SpecPingMailer.ping
      expect(mail.from).not_to include("from@example.com")
    end
  end
end
