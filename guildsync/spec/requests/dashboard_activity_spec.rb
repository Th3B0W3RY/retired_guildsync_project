# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard activity history", type: :request do
  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:guild) { create(:guild, owner: user) }

  describe "GET /dashboard/activity" do
    context "when signed in and MFA-verified" do
      before do
        sign_in user
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      end

      it "renders the activity history page" do
        get dashboard_activity_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(I18n.t("user_activity.history_title"))
      end

      it "lists the user's recorded activities" do
        create(:user_recent_activity, user: user, path: "/guilds/#{guild.id}", label: "Viewed #{guild.name}", link_path: "/guilds/#{guild.id}")
        create(:user_recent_activity, user: user, path: "/auth/discord/callback", label: "Signed in with Discord", link_path: nil)

        get dashboard_activity_path

        expect(response.body).to include("Viewed #{guild.name}")
        expect(response.body).to include("Signed in with Discord")
        expect(response.body).to include("href=\"/guilds/#{guild.id}\"")
        expect(response.body).not_to include("href=\"/auth/discord/callback\"")
      end

      it "does not record itself as an activity" do
        expect {
          get dashboard_activity_path
        }.not_to change { user.user_recent_activities.count }
      end
    end

    it "redirects unauthenticated visitors away from the activity history" do
      get dashboard_activity_path
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include(I18n.t("user_activity.history_title"))
    end
  end
end
