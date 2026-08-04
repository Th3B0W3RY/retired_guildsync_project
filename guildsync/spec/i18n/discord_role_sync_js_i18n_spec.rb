# frozen_string_literal: true

require "rails_helper"

RSpec.describe "I18n: Discord role sync Stimulus messages" do
  let(:required_keys) do
    %w[
      section_title
      missing_role
      generic_error
    ]
  end

  it "defines required keys in every configured locale" do
    I18n.available_locales.each do |locale|
      required_keys.each do |key|
        path = "js.guilds.settings.discord_role_sync.#{key}"
        exists = I18n.exists?(path, locale, fallback: false)
        expect(exists).to eq(true), "missing #{path} for locale #{locale}"

        value = I18n.t(path, locale: locale, default: nil)
        expect(value).to be_present, "blank #{path} for locale #{locale}"
      end
    end
  end
end
