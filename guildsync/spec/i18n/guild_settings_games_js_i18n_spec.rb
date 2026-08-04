# frozen_string_literal: true

require "rails_helper"

RSpec.describe "I18n: guild settings games inline JS strings" do
  let(:required_keys) do
    %w[
      js_no_similar_found
      js_game_exists
      js_confirm_add
      js_search_error
      js_adding
      js_server_error
    ]
  end

  it "defines required keys in every configured locale" do
    I18n.available_locales.each do |locale|
      required_keys.each do |key|
        path = "guilds.settings.games.#{key}"
        exists = I18n.exists?(path, locale, fallback: false)
        expect(exists).to eq(true), "missing #{path} for locale #{locale}"

        value = I18n.t(path, locale: locale, default: nil)
        expect(value).to be_present, "blank #{path} for locale #{locale}"
      end
    end
  end

  it "keeps %{query} and %{name} in js templates when passed-through placeholders are used" do
    # Matches the ERB pattern: t(..., query: "%{query}") leaves "%{query}" for client .replace
    q = I18n.t("guilds.settings.games.js_no_similar_found", locale: :en, query: "%{query}")
    expect(q).to include("%{query}")

    n = I18n.t("guilds.settings.games.js_confirm_add", locale: :en, name: "%{name}")
    expect(n).to include("%{name}")
  end
end
