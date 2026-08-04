# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing and signed-in top bar strip (Figma roadmap parity)", type: :request do
  STRIP_BG = "bg-[rgba(2,6,24,0.88)]"
  STRIP_RULE = "border-b border-white/5"

  shared_examples "includes unified top strip tokens" do
    it "includes roadmap-matched strip background and bottom rule" do
      expect(response.body).to include(STRIP_BG)
      expect(response.body).to include(STRIP_RULE)
    end
  end

  describe "signed-out marketing shells" do
    before { get path }

    context "home landing" do
      let(:path) { root_path }

      include_examples "includes unified top strip tokens"
    end

    context "public pricing" do
      let(:path) { pricing_path }

      include_examples "includes unified top strip tokens"
    end

    context "guest roadmap index" do
      let(:path) { roadmap_path }

      include_examples "includes unified top strip tokens"
    end

    context "sign-in page" do
      let(:path) { login_path }

      include_examples "includes unified top strip tokens"
    end
  end

  describe "signed-out nav alignment vs home" do
    it "uses the same marketing nav inner row tokens as home (login and pricing share max-width track)" do
      nav_track = "max-w-[1680px]"
      inner_row = "mx-auto flex min-h-14 w-full flex-wrap items-center justify-between gap-x-4 gap-y-3 #{nav_track} px-4 py-2 md:h-16 md:px-6 md:py-0"

      get login_path
      expect(response.body).to include(inner_row)

      get pricing_path
      expect(response.body).to include(inner_row)
    end
  end

  describe "signed-in main column (sidebar offset in layout)" do
    it "uses the same strip tokens on the app top bar" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

      get dashboard_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(STRIP_BG)
      expect(response.body).to include(STRIP_RULE)
      expect(response.body).to include("ml-72")
    end
  end
end
