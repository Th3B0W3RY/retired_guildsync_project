# frozen_string_literal: true

require "rails_helper"

RSpec.describe "I18n: home landing feedback carousel copy" do
  let(:required_keys) do
    %w[
      section_title
      carousel_role
      slide_role
      keyboard_hint
      announce_progress
      previous
      next
      pagination
      go_to_slide
    ]
  end

  it "defines required feedback keys in every configured locale" do
    I18n.available_locales.each do |locale|
      required_keys.each do |key|
        path = "home.landing.feedback.#{key}"
        exists = I18n.exists?(path, locale, fallback: false)
        expect(exists).to eq(true), "missing #{path} for locale #{locale}"

        value = I18n.t(path, locale: locale, default: nil)
        expect(value).to be_present, "blank #{path} for locale #{locale}"
      end

      message = I18n.t("home.landing.feedback.go_to_slide", locale: locale, index: 3)
      expect(message).to include("3"), "expected index interpolation in locale #{locale}"
    end
  end
end
