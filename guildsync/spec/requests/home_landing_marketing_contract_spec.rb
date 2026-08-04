# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home landing marketing contract", type: :request do
  it "renders the exact feature-grid helper heading copy" do
    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Click into each table to see what the features actually do!")
  end

  it "renders each feature card as a full-card link to its detail page" do
    create(
      :homepage_feature_card,
      slug: "full_card_click_target",
      title: "Full card click target",
      visible: true,
      position: 0
    )

    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(%(href="/features/full_card_click_target"))
    expect(response.body).to include("block h-full w-full")
    expect(response.body).to include("Full card click target")
  end

  it "renders the user feedback section title exactly when visible entries exist" do
    create(:landing_user_feedback, visible: true, position: 0)

    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to match(%r{<h2\b[^>]*>\s*User Feedback\s*</h2>}m)
  end

  it "renders the user feedback carousel before the feature grid in document order" do
    create(:landing_user_feedback, visible: true, position: 0)
    create(:homepage_feature_card, slug: "order_probe", title: "Order probe", visible: true, position: 99)

    get root_path

    expect(response).to have_http_status(:success)
    body = response.body
    expect(body.index('data-controller="landing-feedback-carousel"')).to be < body.index('id="features"')
  end

  it "renders carousel controls and slide indicators when multiple feedback entries exist" do
    create(:landing_user_feedback, visible: true, position: 0)
    create(:landing_user_feedback, visible: true, position: 1)

    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("landing-feedback-carousel#previous")
    expect(response.body).to include("landing-feedback-carousel#next")
    expect(response.body).to include("data-landing-feedback-carousel-target=\"dot\"")
    expect(response.body.scan("data-landing-feedback-carousel-target=\"dot\"").size).to eq(2)
  end

  it "does not render carousel controls for a single feedback entry" do
    create(:landing_user_feedback, visible: true, position: 0)

    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("landing-feedback-carousel#previous")
    expect(response.body).not_to include("landing-feedback-carousel#next")
    expect(response.body).not_to include("data-landing-feedback-carousel-target=\"dot\"")
  end

  it "renders only visible feedback entries on the homepage" do
    visible = create(:landing_user_feedback, visible: true, position: 0)
    hidden = create(:landing_user_feedback, visible: false, position: 1)

    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(visible.body.to_plain_text)
    expect(response.body).not_to include(hidden.body.to_plain_text)
  end

  it "localizes feedback carousel aria-label strings when locale is German" do
    create(:landing_user_feedback, visible: true, position: 0)
    create(:landing_user_feedback, visible: true, position: 1)

    get root_path, params: { locale: "de" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(I18n.t("home.landing.feedback.previous", locale: :de))
    expect(response.body).to include(I18n.t("home.landing.feedback.next", locale: :de))
    expect(response.body).to include(I18n.t("home.landing.feedback.pagination", locale: :de))
    expect(response.body).to include(
      I18n.t("home.landing.feedback.go_to_slide", locale: :de, index: 1)
    )
  end

  it "renders up to 25 feedback entries on the homepage" do
    LandingUserFeedback::MAX_ENTRIES.times do |idx|
      create(:landing_user_feedback, visible: true, position: idx).update!(body: "<p>feedback-#{idx}</p>")
    end

    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body.scan("data-landing-feedback-carousel-target=\"slide\"").size).to eq(LandingUserFeedback::MAX_ENTRIES)
    expect(response.body).to include("feedback-0")
    expect(response.body).to include("feedback-#{LandingUserFeedback::MAX_ENTRIES - 1}")
  end
end
