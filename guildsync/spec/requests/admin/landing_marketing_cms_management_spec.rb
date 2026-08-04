# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin landing marketing CMS management", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "landing user feedback manager" do
    it "redirects new to index when the max entry limit is reached" do
      LandingUserFeedback::MAX_ENTRIES.times { create(:landing_user_feedback) }

      get "/admin/landing-user-feedbacks/new"

      expect(response).to redirect_to(admin_landing_user_feedbacks_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("admin.landing_user_feedbacks.at_limit", max: LandingUserFeedback::MAX_ENTRIES))
    end

    it "updates visibility and body content" do
      feedback = create(:landing_user_feedback, visible: true)

      patch "/admin/landing-user-feedbacks/#{feedback.id}", params: {
        landing_user_feedback: {
          visible: "0",
          body: "<p>Updated admin feedback body</p>",
        },
      }

      expect(response).to redirect_to(admin_landing_user_feedbacks_path)
      expect(feedback.reload.visible).to eq(false)
      expect(feedback.body.to_plain_text).to include("Updated admin feedback body")
    end

    it "soft-deletes an entry" do
      feedback = create(:landing_user_feedback)

      expect do
        delete "/admin/landing-user-feedbacks/#{feedback.id}"
      end.to change { LandingUserFeedback.active.count }.by(-1)

      expect(response).to redirect_to(admin_landing_user_feedbacks_path)
      expect(feedback.reload).to be_deleted
      expect(LandingUserFeedback.with_deleted.exists?(feedback.id)).to be true
    end

    it "applies reordered feedback positions to homepage rendering order" do
      first = create(:landing_user_feedback, visible: true, position: 0)
      first.update!(body: "<p>feedback-order-first</p>")
      second = create(:landing_user_feedback, visible: true, position: 1)
      second.update!(body: "<p>feedback-order-second</p>")

      patch "/admin/landing-user-feedbacks/reorder", params: { order: [ second.id, first.id ] }
      expect(response).to have_http_status(:ok)

      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body.index("feedback-order-second")).to be < response.body.index("feedback-order-first")
    end
  end

  describe "homepage feature cards/pages editor" do
    it "loads edit page using slug-based admin route params" do
      card = create(:homepage_feature_card, slug: "analytics_insights")

      get edit_admin_homepage_feature_card_path(card)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.homepage_feature_cards.form.body_label"))
      expect(response.body).to include(I18n.t("admin.homepage_feature_cards.form.pick_fa_icon"))
    end

    it "updates card fields and makes the detail page inaccessible when hidden" do
      card = create(:homepage_feature_card, slug: "visibility_toggle_test", visible: true)

      patch admin_homepage_feature_card_path(card), params: {
        homepage_feature_card: {
          slug: "visibility_toggle_test",
          title: "Updated card title",
          description: "Updated card description",
          icon_key: HomepageFeatureCard::ICON_KEYS.second,
          visible: "0",
          body: "<p>Updated detail body from admin edit</p>",
        },
      }

      expect(response).to redirect_to(admin_homepage_feature_cards_path)
      expect(card.reload.visible).to eq(false)
      expect(card.title).to eq("Updated card title")
      expect(card.body.to_plain_text).to include("Updated detail body from admin edit")

      get "/features/visibility_toggle_test"
      expect(response).to have_http_status(:not_found)
    end

    it "soft-deletes card/detail content and removes its public route" do
      card = create(:homepage_feature_card, slug: "delete_me_feature", visible: true)

      expect do
        delete admin_homepage_feature_card_path(card)
      end.to change { HomepageFeatureCard.active.count }.by(-1)

      expect(response).to redirect_to(admin_homepage_feature_cards_path)
      expect(card.reload).to be_deleted

      get "/features/delete_me_feature"
      expect(response).to have_http_status(:not_found)
    end

    it "applies reordered card positions to homepage card order" do
      first = create(
        :homepage_feature_card,
        slug: "card_order_first",
        title: "Card Order First",
        visible: true,
        position: 0
      )
      second = create(
        :homepage_feature_card,
        slug: "card_order_second",
        title: "Card Order Second",
        visible: true,
        position: 1
      )

      patch "/admin/homepage-feature-cards/reorder", params: { order: [ second.id, first.id ] }
      expect(response).to have_http_status(:ok)

      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body.index(%(href="/features/card_order_second"))).to be < response.body.index(%(href="/features/card_order_first"))
    end

    it "uploads a feature detail image through the admin endpoint" do
      image = fixture_file_upload("dot.png", "image/png")

      post upload_image_admin_homepage_feature_cards_path, params: { image: image }

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      expect(payload["url"]).to be_present
      expect(payload["url"]).to start_with("/rails/active_storage/")
    end

    it "blocks image upload when admin session is missing" do
      delete "/admin/logout"
      image = fixture_file_upload("dot.png", "image/png")

      post upload_image_admin_homepage_feature_cards_path, params: { image: image }

      expect(response).to redirect_to(admin_login_path)
    end
  end
end
