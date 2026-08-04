# frozen_string_literal: true

require "rails_helper"

RSpec.describe "JavaScript translations: admin dashboard delete messages" do
  it "defines non-placeholder strings for js.admin.dashboard in every locale" do
    I18n.available_locales.each do |locale|
      I18n.with_locale(locale) do
        # Match real i18n placeholders only: /TODO/i would false-positive on e.g. Spanish "Todos".
        %w[delete_success delete_failed].each do |key|
          text = I18n.t("js.admin.dashboard.#{key}")
          expect(text).not_to match(/TODO_ADMIN/i), "locale #{locale} js.admin.dashboard.#{key}"
        end
        err = I18n.t("js.admin.dashboard.delete_error", error: "x")
        expect(err).not_to match(/TODO_ADMIN/i), "locale #{locale} js.admin.dashboard.delete_error"
      end
    end
  end
end
