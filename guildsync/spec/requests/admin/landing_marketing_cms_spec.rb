# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin landing marketing CMS", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  describe "guest access" do
    it "redirects GET /admin/landing-user-feedbacks to admin login" do
      get "/admin/landing-user-feedbacks"

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects GET /admin/homepage-feature-cards to admin login" do
      get "/admin/homepage-feature-cards"

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects GET /admin/landing-user-feedbacks/new without admin session" do
      get "/admin/landing-user-feedbacks/new"

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects GET /admin/homepage-feature-cards/new without admin session" do
      get "/admin/homepage-feature-cards/new"

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects GET /admin/landing-user-feedbacks/:id/edit without admin session" do
      feedback = create(:landing_user_feedback)

      get "/admin/landing-user-feedbacks/#{feedback.id}/edit"

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects GET /admin/homepage-feature-cards/:id/edit without admin session" do
      card = create(:homepage_feature_card)

      get "/admin/homepage-feature-cards/#{card.id}/edit"

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects GET /admin/fontawesome-free-icons without admin session" do
      get "/admin/fontawesome-free-icons", headers: { "Accept" => "application/json" }

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects PATCH reorder for landing-user-feedbacks without admin session" do
      a = create(:landing_user_feedback)
      b = create(:landing_user_feedback)
      positions_before = [ a.reload.position, b.reload.position ]

      patch "/admin/landing-user-feedbacks/reorder", params: { order: [ b.id, a.id ] }

      expect(response).to redirect_to(admin_login_path)
      expect([ a.reload.position, b.reload.position ]).to eq(positions_before)
    end

    it "redirects PATCH carousel-settings for landing-user-feedbacks without admin session" do
      patch "/admin/landing-user-feedbacks/carousel-settings", params: { carousel_interval_seconds: 10 }

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects PATCH reorder for homepage-feature-cards without admin session" do
      a = create(:homepage_feature_card)
      b = create(:homepage_feature_card)
      positions_before = [ a.reload.position, b.reload.position ]

      patch "/admin/homepage-feature-cards/reorder", params: { order: [ b.id, a.id ] }

      expect(response).to redirect_to(admin_login_path)
      expect([ a.reload.position, b.reload.position ]).to eq(positions_before)
    end

    it "redirects POST /admin/landing-user-feedbacks without admin session and does not create a row" do
      expect do
        post "/admin/landing-user-feedbacks", params: {
          landing_user_feedback: { visible: "1", body: "<p>Injected</p>" }
        }
      end.not_to change(LandingUserFeedback, :count)

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects POST /admin/homepage-feature-cards without admin session and does not create a row" do
      expect do
        post "/admin/homepage-feature-cards", params: {
          homepage_feature_card: {
            slug: "guest_inject",
            title: "Injected",
            description: "Short.",
            icon_key: HomepageFeatureCard::ICON_KEYS.first,
            visible: "1",
            body: "<p>No</p>"
          }
        }
      end.not_to change(HomepageFeatureCard, :count)

      expect(response).to redirect_to(admin_login_path)
    end

    it "redirects DELETE /admin/landing-user-feedbacks/:id without session and keeps the row" do
      feedback = create(:landing_user_feedback)

      expect do
        delete "/admin/landing-user-feedbacks/#{feedback.id}"
      end.not_to change(LandingUserFeedback, :count)

      expect(response).to redirect_to(admin_login_path)
      expect(LandingUserFeedback.exists?(feedback.id)).to be true
    end

    it "redirects DELETE /admin/homepage-feature-cards/:id without session and keeps the row" do
      card = create(:homepage_feature_card)

      expect do
        delete "/admin/homepage-feature-cards/#{card.id}"
      end.not_to change(HomepageFeatureCard, :count)

      expect(response).to redirect_to(admin_login_path)
      expect(HomepageFeatureCard.exists?(card.id)).to be true
    end

    it "redirects PATCH update on landing-user-feedbacks without session and does not change body" do
      feedback = create(:landing_user_feedback)
      plain_before = feedback.body.to_plain_text

      patch "/admin/landing-user-feedbacks/#{feedback.id}", params: {
        landing_user_feedback: { visible: "0", body: "<p>Unauthorized change</p>" }
      }

      expect(response).to redirect_to(admin_login_path)
      feedback.reload
      expect(feedback.body.to_plain_text).to eq(plain_before)
      expect(feedback).to be_visible
    end

    it "redirects PATCH update on homepage-feature-cards without session and does not change title" do
      card = create(:homepage_feature_card, title: "Original marketing title")

      patch "/admin/homepage-feature-cards/#{card.id}", params: {
        homepage_feature_card: {
          slug: card.slug,
          title: "Hacked title",
          description: card.description,
          icon_key: card.icon_key,
          visible: card.visible ? "1" : "0"
        }
      }

      expect(response).to redirect_to(admin_login_path)
      expect(card.reload.title).to eq("Original marketing title")
    end
  end

  describe "when signed in as admin" do
    before do
      ENV["ADMIN_EMAIL"] = admin_email
      ENV["ADMIN_PASSWORD"] = admin_password
      post "/admin/login", params: { email: admin_email, password: admin_password }
    end

    after do
      ENV.delete("ADMIN_EMAIL")
      ENV.delete("ADMIN_PASSWORD")
    end

    it "shows both homepage CMS quick actions on the admin dashboard" do
      get "/admin"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.user_feedback_manager"))
      expect(response.body).to include(I18n.t("admin.dashboard.quick_actions.homepage_feature_cards"))
    end

    describe "Landing user feedback" do
      it "lists entries" do
        create(:landing_user_feedback)

        get "/admin/landing-user-feedbacks"

        expect(response).to have_http_status(:success)
        expect(response.body).to include(I18n.t("admin.landing_user_feedbacks.page_title"))
      end

      it "shows carousel interval settings" do
        get "/admin/landing-user-feedbacks"

        expect(response.body).to include(I18n.t("admin.landing_user_feedbacks.carousel_settings.heading"))
      end

      it "updates carousel interval via PATCH" do
        patch "/admin/landing-user-feedbacks/carousel-settings", params: { carousel_interval_seconds: 12 }

        expect(response).to redirect_to(admin_landing_user_feedbacks_path)
        expect(SiteSetting.get("landing_feedback_carousel_interval_ms")).to eq("12000")
      end

      it "clamps carousel interval to the allowed second range" do
        patch "/admin/landing-user-feedbacks/carousel-settings", params: { carousel_interval_seconds: 999 }
        expect(SiteSetting.get("landing_feedback_carousel_interval_ms")).to eq("60000")

        patch "/admin/landing-user-feedbacks/carousel-settings", params: { carousel_interval_seconds: 0 }
        expect(SiteSetting.get("landing_feedback_carousel_interval_ms")).to eq("2000")
      end

      it "reorders via PATCH" do
        a = create(:landing_user_feedback)
        b = create(:landing_user_feedback)

        patch "/admin/landing-user-feedbacks/reorder", params: { order: [ b.id, a.id ] }

        expect(response).to have_http_status(:ok)
        expect(b.reload.position).to eq(0)
        expect(a.reload.position).to eq(1)
      end

      it "returns unprocessable when reorder payload omits an id" do
        a = create(:landing_user_feedback)
        b = create(:landing_user_feedback)
        positions_before = [ a.reload.position, b.reload.position ]

        patch "/admin/landing-user-feedbacks/reorder", params: { order: [ b.id ] }

        expect(response).to have_http_status(:unprocessable_entity)
        expect([ a.reload.position, b.reload.position ]).to eq(positions_before)
      end

      it "blocks the 26th create" do
        LandingUserFeedback::MAX_ENTRIES.times { create(:landing_user_feedback) }

        expect(LandingUserFeedback.count).to eq(LandingUserFeedback::MAX_ENTRIES)

        post "/admin/landing-user-feedbacks", params: {
          landing_user_feedback: { visible: "1", body: "<p>Too many</p>" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(LandingUserFeedback.count).to eq(LandingUserFeedback::MAX_ENTRIES)
      end

      it "creates a visible rich text entry from admin" do
        post "/admin/landing-user-feedbacks", params: {
          landing_user_feedback: { visible: "1", body: "<p>Members love the faster onboarding flow.</p>" }
        }

        expect(response).to redirect_to(admin_landing_user_feedbacks_path)
        expect(LandingUserFeedback.count).to eq(1)
        expect(LandingUserFeedback.last).to be_visible
        expect(LandingUserFeedback.last.body.to_plain_text).to include("Members love the faster onboarding flow.")
      end

      it "updates visibility and rich text from admin" do
        feedback = create(:landing_user_feedback, visible: true)

        patch "/admin/landing-user-feedbacks/#{feedback.id}", params: {
          landing_user_feedback: { visible: "0", body: "<p>Revised testimonial copy</p>" }
        }

        expect(response).to redirect_to(admin_landing_user_feedbacks_path)
        feedback.reload
        expect(feedback).not_to be_visible
        expect(feedback.body.to_plain_text).to include("Revised testimonial copy")
      end

      it "soft-deletes a feedback entry" do
        feedback = create(:landing_user_feedback)

        expect do
          delete "/admin/landing-user-feedbacks/#{feedback.id}"
        end.to change { LandingUserFeedback.active.count }.by(-1)

        expect(response).to redirect_to(admin_landing_user_feedbacks_path)
        expect(feedback.reload).to be_deleted
      end
    end

    describe "Homepage feature cards" do
      it "lists cards" do
        create(:homepage_feature_card)

        get "/admin/homepage-feature-cards"

        expect(response).to have_http_status(:success)
        expect(response.body).to include(I18n.t("admin.homepage_feature_cards.page_title"))
      end

      it "links each row to the public /features/:slug detail page" do
        create(:homepage_feature_card, slug: "admin_preview_slug", visible: true)

        get "/admin/homepage-feature-cards"

        expect(response).to have_http_status(:success)
        expect(response.body).to include(homepage_feature_path("admin_preview_slug"))
        expect(response.body).to include(I18n.t("admin.homepage_feature_cards.view_public"))
      end

      it "surfaces a newly created visible card on the marketing detail route" do
        post "/admin/homepage-feature-cards", params: {
          homepage_feature_card: {
            slug: "cms_from_admin",
            title: "Created via admin",
            description: "Short grid copy for the landing card.",
            icon_key: HomepageFeatureCard::ICON_KEYS.first,
            visible: "1",
            body: "<p>Detail body from admin create</p>"
          }
        }

        expect(response).to redirect_to(admin_homepage_feature_cards_path)

        get "/features/cms_from_admin"

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Created via admin")
        expect(response.body).to include("Detail body from admin create")
      end

      it "reorders via PATCH" do
        a = create(:homepage_feature_card)
        b = create(:homepage_feature_card)

        patch "/admin/homepage-feature-cards/reorder", params: { order: [ b.id, a.id ] }

        expect(response).to have_http_status(:ok)
        expect(b.reload.position).to eq(0)
        expect(a.reload.position).to eq(1)
      end

      it "returns unprocessable when reorder payload omits an id" do
        a = create(:homepage_feature_card)
        b = create(:homepage_feature_card)
        positions_before = [ a.reload.position, b.reload.position ]

        patch "/admin/homepage-feature-cards/reorder", params: { order: [ b.id ] }

        expect(response).to have_http_status(:unprocessable_entity)
        expect([ a.reload.position, b.reload.position ]).to eq(positions_before)
      end

      it "creates a card and its editable detail page body from admin" do
        post "/admin/homepage-feature-cards", params: {
          homepage_feature_card: {
            slug: "automation_tools",
            title: "Automation tools",
            description: "Automate recurring guild workflows.",
            icon_key: "automation_tools",
            visible: "1",
            body: "<p>Detailed automation help text.</p>"
          }
        }

        expect(response).to redirect_to(admin_homepage_feature_cards_path)

        card = HomepageFeatureCard.find_by!(slug: "automation_tools")
        expect(card.title).to eq("Automation tools")
        expect(card).to be_visible
        expect(card.body.to_plain_text).to include("Detailed automation help text.")
      end

      it "updates card fields from admin" do
        card = create(:homepage_feature_card, title: "Before title", visible: true)

        patch "/admin/homepage-feature-cards/#{card.id}", params: {
          homepage_feature_card: {
            slug: card.slug,
            title: "After title",
            description: "Updated short description for the grid.",
            icon_key: card.icon_key,
            visible: "0",
            body: "<p>Updated detail page body.</p>"
          }
        }

        expect(response).to redirect_to(admin_homepage_feature_cards_path)
        card.reload
        expect(card.title).to eq("After title")
        expect(card.description).to eq("Updated short description for the grid.")
        expect(card).not_to be_visible
        expect(card.body.to_plain_text).to include("Updated detail page body.")
      end

      it "soft-deletes a feature card" do
        card = create(:homepage_feature_card)

        expect do
          delete "/admin/homepage-feature-cards/#{card.id}"
        end.to change { HomepageFeatureCard.active.count }.by(-1)

        expect(response).to redirect_to(admin_homepage_feature_cards_path)
        expect(card.reload).to be_deleted
      end
    end
  end
end
