# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Trusted external redirects (SiteSetting URLs)", type: :request do
  describe "GET /release-notes" do
    it "falls back to root when release notes URL is not http(s)" do
      SiteSetting.set("release_notes_url", "javascript:void(0)")

      get release_notes_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.application.invalid_external_redirect"))
    end
  end

  describe "GET /support/contact (signed in)" do
    let(:user) { create(:user, :discord_auth) }

    before { sign_in user }

    it "falls back to dashboard when support redirect URL is not http(s)" do
      SiteSetting.set("release_notes_url", "data:text/html,<script>bad</script>")

      get contact_support_path

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.application.invalid_external_redirect"))
    end
  end
end
