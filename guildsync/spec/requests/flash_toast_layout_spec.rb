# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Flash toast layout (main-column band)", type: :request do
  describe "desktop layout" do
    it "uses a full-viewport horizontal band when the persistent sidebar is hidden" do
      get root_path

      expect(response.body).to include('data-controller="toast"')
      expect(response.body).to include("left-0")
      expect(response.body).to include("right-0")
      expect(response.body).not_to include("left-72")
    end

    it "insets the toast band to the main column when the sidebar is visible" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

      get dashboard_path

      expect(response.body).to include('data-controller="toast"')
      expect(response.body).to include("left-72")
      expect(response.body).to include("right-0")
      expect(response.body).to include("ml-72")
    end
  end

  describe "mobile HTML variant" do
    it "uses a full-width band when signed in (drawer sidebar does not inset layout)" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

      get dashboard_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response.body).to include('data-controller="toast"')
      expect(response.body).to include("left-0")
      expect(response.body).to include("right-0")
      expect(response.body).not_to include("left-72")
    end
  end
end
