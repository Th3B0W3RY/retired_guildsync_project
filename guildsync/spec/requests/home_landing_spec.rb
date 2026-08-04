# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home landing page", type: :request do
  before do
    HomepageFeatureCard.find_or_create_by!(slug: "member_management") do |c|
      c.title = I18n.t("home.landing.features_grid.member_management.title", locale: :en)
      c.description = I18n.t("home.landing.features_grid.member_management.desc", locale: :en)
      c.icon_key = "member_management"
      c.position = 0
      c.visible = true
    end
  end

  it "links a compiled Tailwind stylesheet so the landing page is not unstyled in dev/prod" do
    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to match(%r{/assets/tailwind[^"'>\s]+\.css})
  end

  it "exposes extended marketing copy keys for EN and DE (admin compare / future sections)" do
    expect(I18n.t("home.landing.hero_kicker", locale: :en)).to be_present
    expect(I18n.t("home.landing.feature_spotlight.title", locale: :en)).to be_present
    expect(I18n.t("home.landing.compare_new_1", locale: :de)).to be_present
  end

  describe "user feedback carousel (marketing CMS)" do
    it "renders carousel wiring and title when visible entries exist" do
      create(:landing_user_feedback, position: 0)

      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("home.landing.feedback.section_title"))
      expect(response.body).to include("landing-feedback-carousel")
      default_ms = SiteSetting::LANDING_FEEDBACK_CAROUSEL_INTERVAL_DEFAULT_MS
      expect(response.body).to include("data-landing-feedback-carousel-interval-value=\"#{default_ms}\"")
      expect(response.body).to include("data-landing-feedback-carousel-announce-template-value=")
      expect(response.body).to include(I18n.t("home.landing.feedback.announce_progress"))
      feedback_title = I18n.t("home.landing.feedback.section_title")
      expect(response.body).to match(%r{<h2\b[^>]*>[\s\n]*#{Regexp.escape(feedback_title)}[\s\n]*</h2>}m)
    end

    it "uses the configured carousel interval from site settings" do
      SiteSetting.set("landing_feedback_carousel_interval_ms", "9000")
      create(:landing_user_feedback, position: 0)

      get root_path

      expect(response.body).to include("data-landing-feedback-carousel-interval-value=\"9000\"")
    end

    it "omits the feedback section when there are no visible entries" do
      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("landing-feedback-carousel")
    end

    it "places the feedback carousel before the features block (headline + grid) when entries exist" do
      create(:landing_user_feedback)

      get root_path

      body = response.body
      expect(body.index("data-controller=\"landing-feedback-carousel\"")).to be < body.index('id="features"')
    end

    it "uses one unified features section padding under the hero" do
      get root_path

      expect(response.body).to include("px-4 pt-6 sm:pt-8 md:pt-10 pb-20 sm:pb-24")
    end
  end

  describe "landing marketing snapshot import (test env — production requires FORCE_LANDING_MARKETING_IMPORT)" do
    let(:snapshot_path) { Rails.root.join("spec/fixtures/files/landing_marketing/marketing_snapshot_minimal.yml") }

    before do
      LandingMarketing::Snapshot::Importer.new(path: snapshot_path).call
    end

    it "renders imported feature card title and comparison row on the guest landing page" do
      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Spec Snapshot Title")
      expect(response.body).to include("Spec Compare Row Alpha")
      expect(response.body).to include(homepage_feature_path("member_management"))
    end
  end

  describe "guest landing reads Homepage & guest marketing from the database" do
    it "renders the feature card title stored in the DB" do
      card = HomepageFeatureCard.find_by!(slug: "member_management")
      card.update!(title: "DB Authoritative Feature Title For Spec")

      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("DB Authoritative Feature Title For Spec")
    end
  end

  it "renders Figma-aligned homepage sections from i18n" do
    get root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(I18n.t("home.landing.title"))
    expect(response.body).to include(I18n.t("home.landing.subtitle"))
    expect(response.body).to include(I18n.t("home.landing.cta.button_hero"))
    expect(response.body).to include(I18n.t("home.landing.explore_pricing"))
    expect(response.body).to include(I18n.t("home.landing.why_title"))
    expect(response.body).to include(I18n.t("home.landing.features_cta_hint"))
    expect(response.body).to include(I18n.t("home.landing.features_section_subtitle"))
    expect(response.body).to include("Click into each table to see what the features actually do!")
    why = I18n.t("home.landing.why_title")
    hint = I18n.t("home.landing.features_cta_hint")
    expect(response.body).to match(%r{<h2\b[^>]*>[\s\n]*#{Regexp.escape(why)}[\s\n]*</h2>}m)
    expect(response.body).to match(%r{<h3\b[^>]*>[\s\n]*#{Regexp.escape(hint)}[\s\n]*</h3>}m)
    expect(response.body).to include(I18n.t("home.landing.features_grid.member_management.title"))
    expect(response.body).to include(homepage_feature_path("member_management"))
    expect(response.body).to include(I18n.t("home.landing.compare_title"))
    expect(response.body).to include(I18n.t("home.landing.compare.features.rapid_user_feedback"))
    expect(response.body).to include(I18n.t("home.landing.compare.features.custom_role_system"))
    expect(response.body).to include(I18n.t("home.landing.compare.competitor_3"))
    expect(response.body).to include(I18n.t("home.landing.cta.title"))
    expect(response.body).to include(I18n.t("home.landing.cta.button"))
    expect(response.body).to include(I18n.t("home.landing.footer_copyright", year: Time.current.year))
    expect(response.body).not_to include("Watch 90-sec Demo")

    expect(response.body).to include("landing-hero-cinematic")
    expect(response.body.scan(%r{src="[^"]*hero-background[^"]*\.mp4}).size).to eq(2)
    expect(response.body).to match(%r{/assets/landing/hero-poster[^"']+\.jpg})
    expect(response.body).to match(/id="features"/)
    expect(response.body).to include('id="guest-beta-discord-banner"')
    expect(response.body).to include(I18n.t("layouts.application.beta_banner.join_discord"))
    expect(response.body).to match(/<video\b[^>]*\bmuted\b/m)
    expect(response.body).not_to match(/<video\b[^>]*\bloop\b/m)
    expect(response.body).to match(/<video\b[^>]*\bplaysinline/m)
    expect(response.body).to match(/<video\b[^>]*\bautoplay/m)
    expect(response.body).to match(/preload="auto"/)
  end

  describe "footer links" do
    it "includes dedicated support redirect routes in the guest landing HTML" do
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(footer_support_documentation_path)
      expect(response.body).to include(footer_support_contact_path)
      expect(response.body).to include(footer_support_discord_path)
    end

    it "includes dedicated support redirect routes on the mobile variant" do
      get root_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(footer_support_documentation_path)
      expect(response.body).to include(footer_support_contact_path)
      expect(response.body).to include(footer_support_discord_path)
    end

    it "includes legal page links when configured content exists in the database" do
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(privacy_policy_path)
      expect(response.body).to include(terms_of_service_path)
      expect(response.body).to include(security_page_path)
    end

    it "includes legal page links on mobile variant" do
      get root_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(privacy_policy_path)
      expect(response.body).to include(terms_of_service_path)
      expect(response.body).to include(security_page_path)
    end
  end
end
