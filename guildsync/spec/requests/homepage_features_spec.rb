# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Homepage feature pages", type: :request do
  describe "GET /features/:slug" do
    it "renders rich detail for a visible card" do
      card = create(:homepage_feature_card, slug: "member_management", title: "Member tools", visible: true)
      card.update!(body: "<p>Deep dive content</p>")

      get homepage_feature_path("member_management")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Member tools")
      expect(response.body).to include("Deep dive content")
      expect(response.body).to match(%r{<title>\s*Member tools — })
      expect(response.body).to include(%(name="description"))
      expect(response.body).to include(%(property="og:type"))
      expect(response.body).to include(%(property="og:url"))
      expect(response.body).to include(homepage_feature_url("member_management"))
      expect(response.body).to include(%(name="twitter:card"))
      expect(response.body).to include(%(property="og:image"))
      expect(response.body).to include(%(name="twitter:image"))
      expect(response.body).to include("apple-touch-icon-1024x1024")
      expect(response.body).to include(%(rel="canonical"))
    end

    it "returns not found when the card is hidden" do
      create(:homepage_feature_card, slug: "hidden_card", visible: false)

      get homepage_feature_path("hidden_card")

      expect(response).to have_http_status(:not_found)
    end

    it "returns not found for an unknown slug" do
      get homepage_feature_path("no_such_marketing_slug")

      expect(response).to have_http_status(:not_found)
    end

    it "shows the empty-detail copy when rich text body is blank HTML only" do
      card = create(:homepage_feature_card, slug: "empty_body_card", title: "Empty body", visible: true, description: "Short summary for SEO.")
      card.update!(body: "<div class=\"trix-content\">\n<br>\n</div>")

      get homepage_feature_path("empty_body_card")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Short summary for SEO.")
      expect(response.body).to include(I18n.t("homepage_features.empty_detail"))
    end

    it "uses the mobile marketing flush shell and loads Inter for the mobile variant" do
      create(:homepage_feature_card, slug: "mobile_marketing_shell", title: "Mobile marketing", visible: true)

      get homepage_feature_path("mobile_marketing_shell"), headers: mobile_user_agent_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include("fonts.googleapis.com/css2?family=Inter")
      expect(response.body).not_to include("rounded-xl border border-white/10 bg-[rgba(15,23,43,0.5)]")
    end
  end
end
