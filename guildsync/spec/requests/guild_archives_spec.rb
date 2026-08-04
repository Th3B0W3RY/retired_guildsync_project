# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GuildArchives", type: :request do
  let(:owner) do
    u = build(:user, :discord_auth, skip_free_plan_subscription: true)
    u.save!
    u
  end
  let(:pricing_plan) { create(:pricing_plan, name: "Archive Plan", max_guilds: 2, price: 10, price_display: "$10", period: "month") }
  let!(:subscription) { create(:subscription, user: owner, pricing_plan: pricing_plan, status: :active, started_at: Time.current) }
  let!(:guild) { create(:guild, owner: owner, name: "Soul Society") }

  before { sign_in owner }

  describe "POST /guilds/:id/archive" do
    it "archives a guild when the typed name matches" do
      post archive_guild_path(guild), params: { guild_name_confirmation: "Soul Society" }

      expect(response).to redirect_to(guild_archives_path)
      expect(flash[:notice]).to eq(I18n.t("guild_archives.alerts.archived_success", guild_name: "Soul Society"))
      guild.reload
      expect(guild.archived_at).to be_present
      expect(guild.scheduled_purge_at).to be_present
      expect(guild.scheduled_purge_at).to be_within(2.seconds).of(guild.archived_at + Guild::ARCHIVE_RETENTION_PERIOD)
    end

    it "rejects archive when typed name does not match" do
      post archive_guild_path(guild), params: { guild_name_confirmation: "Wrong Name" }

      expect(response).to redirect_to(guild_settings_path(guild))
      expect(flash[:alert]).to eq(I18n.t("guild_archives.alerts.name_confirmation_mismatch"))
      expect(guild.reload.archived_at).to be_nil
    end
  end

  describe "GET /guilds/:id for archived guild" do
    it "redirects to archived guilds page" do
      guild.update!(archived_at: 1.hour.ago, scheduled_purge_at: 1.year.from_now)

      get guild_path(guild)

      expect(response).to redirect_to(guild_archives_path)
    end

    it "blocks archived guild message center access" do
      guild.update!(archived_at: 1.hour.ago, scheduled_purge_at: 1.year.from_now)

      get guild_message_center_path(guild)

      expect(response).to redirect_to(guild_archives_path)
    end
  end

  describe "GET /guild_archives" do
    it "lists only the owner's archived guilds" do
      guild.update!(archived_at: 1.hour.ago, scheduled_purge_at: 1.year.from_now)

      get guild_archives_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Soul Society")
    end

    it "shows recovery messaging without legacy wording or stray punctuation markup" do
      # Force English via query—user preferred_locale/browser may otherwise render another locale.
      get guild_archives_path(locale: :en)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("guild_archives.index.long_recovery_hint", locale: :en))
      expect(response.body).to include(I18n.t("guild_archives.index.subtitle", locale: :en))
      expect(response.body).to include(I18n.t("guild_archives.index.recovery_note_label", locale: :en))

      expect(response.body).not_to include("more than 6 months")
      expect(response.body).not_to include("restore tools")
      expect(response.body).not_to include(%(aria-hidden="true">!</span>))
    end

    it "shows translated recovery copy when locale query param selects another language" do
      get guild_archives_path(params: { locale: "de" })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("guild_archives.index.long_recovery_hint", locale: :de))
      expect(response.body).to include(I18n.t("guild_archives.index.recovery_note_label", locale: :de))
      expect(response.body).to include(I18n.t("guild_archives.index.subtitle", locale: :de))
    end
  end

  describe "GET /guild_archives support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    before do
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      guild.update!(archived_at: 1.hour.ago, scheduled_purge_at: 1.year.from_now)
    end

    it "includes default support URL in HTML" do
      get guild_archives_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get guild_archives_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://guild-archives-support.example/help")
      get guild_archives_path
      expect(response.body).to include("https://guild-archives-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://guild-archives-support.example/help")
      get guild_archives_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://guild-archives-support.example/help")
    end
  end

  describe "POST /guild_archives/:id/unarchive" do
    it "unarchives the guild and clears scheduled purge when plan allows" do
      guild.update!(archived_at: 1.day.ago, scheduled_purge_at: 6.months.from_now)

      post unarchive_guild_archive_path(guild)

      expect(response).to redirect_to(guild_archives_path)
      expect(flash[:notice]).to eq(I18n.t("guild_archives.alerts.unarchived_success", guild_name: guild.name))
      expect(guild.reload.archived_at).to be_nil
      expect(guild.scheduled_purge_at).to be_nil
    end

    it "blocks unarchive when active guild limit is reached" do
      archived_guild = create(:guild, owner: owner, archived_at: 1.day.ago, scheduled_purge_at: 1.year.from_now)
      pricing_plan.update!(max_guilds: 1)

      post unarchive_guild_archive_path(archived_guild)

      expect(response).to redirect_to(guild_archives_path)
      expect(flash[:alert]).to eq(I18n.t("guild_archives.alerts.unarchive_plan_limit"))
      expect(archived_guild.reload.archived_at).to be_present
    end
  end

  describe "DELETE /guild_archives/:id" do
    it "blocks permanent delete before retention period" do
      guild.update!(archived_at: 1.day.ago, scheduled_purge_at: 6.months.from_now)

      expect {
        delete guild_archive_path(guild)
      }.not_to change(Guild, :count)

      expect(response).to redirect_to(guild_archives_path)
      expect(flash[:alert]).to eq(I18n.t("guild_archives.alerts.purge_not_ready"))
    end

    it "permanently deletes archived guilds after retention period" do
      guild.update!(archived_at: 1.year.ago - 1.day, scheduled_purge_at: 1.day.ago)
      name = guild.name

      expect {
        delete guild_archive_path(guild)
      }.to change(Guild, :count).by(-1)

      expect(response).to redirect_to(guild_archives_path)
      expect(flash[:notice]).to eq(I18n.t("guild_archives.alerts.purged_success", guild_name: name))
    end
  end

  describe "access isolation" do
    let(:other_owner) do
      u = build(:user, :discord_auth, skip_free_plan_subscription: true)
      u.save!
      u
    end
    let!(:other_subscription) do
      create(:subscription, user: other_owner, pricing_plan: pricing_plan, status: :active, started_at: Time.current)
    end
    let!(:foreign_guild) { create(:guild, owner: other_owner, name: "Foreign Hall") }

    it "blocks a member who is not the owner from archiving the guild" do
      foreign_guild.guild_members.find_or_create_by!(user: owner) do |m|
        m.status = :active
        m.role = :member
      end

      post archive_guild_path(foreign_guild), params: { guild_name_confirmation: "Foreign Hall" }

      expect(response).to redirect_to(guild_path(foreign_guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.owner_only"))
      expect(foreign_guild.reload.archived_at).to be_nil
    end

    it "redirects when the user has no relationship to the guild" do
      intruder = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: intruder, pricing_plan: pricing_plan, status: :active, started_at: Time.current)
      sign_in intruder

      post archive_guild_path(guild), params: { guild_name_confirmation: "Soul Society" }

      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
      expect(guild.reload.archived_at).to be_nil
    end

    it "does not let another user unarchive an archived guild they do not own" do
      guild.update!(archived_at: 1.hour.ago, scheduled_purge_at: 1.year.from_now)
      intruder = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: intruder, pricing_plan: pricing_plan, status: :active, started_at: Time.current)
      sign_in intruder

      post unarchive_guild_archive_path(guild)

      expect(response).to redirect_to(guild_archives_path)
      expect(flash[:alert]).to eq(I18n.t("guild_archives.alerts.not_found"))
      expect(guild.reload.archived_at).to be_present
    end

    it "does not let another user purge-delete an archived guild they do not own" do
      guild.update!(archived_at: 1.year.ago, scheduled_purge_at: 1.day.ago)
      intruder = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: intruder, pricing_plan: pricing_plan, status: :active, started_at: Time.current)
      sign_in intruder

      expect {
        delete guild_archive_path(guild)
      }.not_to change(Guild, :count)

      expect(response).to redirect_to(guild_archives_path)
      expect(flash[:alert]).to eq(I18n.t("guild_archives.alerts.not_found"))
      expect(Guild.exists?(guild.id)).to be true
    end
  end

  describe "authentication" do
    before { sign_out owner }

    it "requires sign-in for the archived guilds index" do
      get guild_archives_path
      expect(response).to redirect_to(login_path)
    end

    it "requires sign-in to archive" do
      post archive_guild_path(guild), params: { guild_name_confirmation: "Soul Society" }
      expect(response).to redirect_to(login_path)
      expect(guild.reload.archived_at).to be_nil
    end
  end
end
