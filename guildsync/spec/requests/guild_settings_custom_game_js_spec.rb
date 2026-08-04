# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild settings custom game inline JS (i18n placeholders)", type: :request do
  let(:owner) do
    u = build(:user, skip_free_plan_subscription: true)
    u.auth_method = "discord"
    u.save!
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: owner, pricing_plan: pricing_plan) }
  let!(:guild) { create(:guild, owner: owner) }

  before do
    sign_in owner
    set_mfa_verified_in_session
  end

  shared_examples "settings page embeds client-side i18n placeholders" do
    it "leaves %{query} and %{name} for .replace() so the game name is not empty" do
      expect(response.body).to include(".replace('%{query}', query)")
      expect(response.body).to include(".replace('%{name}', selectedGameName)")
      expect(response.body).to include(".replace('%{name}', data.exact_match.name)")
      expect(response.body).to include("%{query}")
      expect(response.body).to include("%{name}")
    end

    it "does not HTML-entity-quote the confirm template (avoids literal &quot; in dialogs)" do
      expect(response.body).not_to include("Are you sure you want to add &quot;")
      expect(response.body).not_to include("Click &quot;Add Game&quot;")
    end
  end

  describe "GET /guilds/:id/settings (desktop)" do
    before { get guild_settings_path(guild), headers: { "User-Agent" => MobileVariantRequestHelpers::DESKTOP_CHROME_UA } }

    include_examples "settings page embeds client-side i18n placeholders"
  end

  describe "GET /guilds/:id/settings (mobile variant)" do
    before { get guild_settings_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA) }

    include_examples "settings page embeds client-side i18n placeholders"
  end
end
