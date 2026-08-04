# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildSync::SmtpPassword do
  describe ".require_for_production!" do
    it "returns the password when set" do
      old = ENV["SMTP_PASSWORD"]
      ENV["SMTP_PASSWORD"] = "secret-key"
      begin
        expect(described_class.require_for_production!).to eq("secret-key")
      ensure
        ENV["SMTP_PASSWORD"] = old
      end
    end

    it "raises when unset" do
      old = ENV["SMTP_PASSWORD"]
      ENV.delete("SMTP_PASSWORD")
      begin
        expect { described_class.require_for_production! }.to raise_error(ArgumentError, /SMTP_PASSWORD must be set/)
      ensure
        if old.nil?
          ENV.delete("SMTP_PASSWORD")
        else
          ENV["SMTP_PASSWORD"] = old
        end
      end
    end

    it "raises when blank or whitespace-only" do
      old = ENV["SMTP_PASSWORD"]
      begin
        [ "", " ", "\t" ].each do |bad|
          ENV["SMTP_PASSWORD"] = bad
          expect { described_class.require_for_production! }.to raise_error(ArgumentError, /SMTP_PASSWORD must be set/)
        end
      ensure
        ENV["SMTP_PASSWORD"] = old
      end
    end
  end
end
