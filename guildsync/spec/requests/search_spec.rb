# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Search", type: :request do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }

  before do
    # Ensure guild membership exists for owner
    guild.guild_members.find_or_create_by!(user: user) do |m|
      m.status = :active
      m.role = :owner
    end
    user.update!(auth_method: :discord)
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    sign_in user
  end

  describe "GET /search" do
    context "when Typesense is not enabled" do
      before do
        allow(TypesenseConfig).to receive(:enabled?).and_return(false)
      end

      it "still returns page results" do
        get search_path, params: { q: "settings" }, as: :json
        expect(response).to have_http_status(:ok)
        
        json = JSON.parse(response.body)
        expect(json["results"]).to be_an(Array)
        # Should find settings pages even without Typesense
        expect(json["results"].any? { |r| r["title"].downcase.include?("settings") }).to be true
      end
    end

    context "with empty query" do
      it "returns empty results" do
        get search_path, params: { q: "" }, as: :json
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["results"]).to eq([])
        expect(json["total"]).to eq(0)
      end
    end

    context "with blank query" do
      it "returns empty results" do
        get search_path, params: { q: "   " }, as: :json
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["results"]).to eq([])
      end
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to login" do
        get search_path, params: { q: "test" }
        expect(response).to redirect_to(login_path)
      end
    end

    context "searching for pages" do
      before do
        allow(TypesenseConfig).to receive(:enabled?).and_return(false)
      end

      it "finds global pages like Dashboard" do
        get search_path, params: { q: "dashboard" }, as: :json
        json = JSON.parse(response.body)
        
        expect(json["results"].any? { |r| r["title"] == "Dashboard" }).to be true
      end

      it "finds guild settings for owned guilds" do
        get search_path, params: { q: "settings" }, as: :json
        json = JSON.parse(response.body)
        
        # Should find both Account Settings and Guild Settings
        titles = json["results"].map { |r| r["title"] }
        expect(titles).to include("Account Settings")
        expect(titles.any? { |t| t.include?("Guild Settings") }).to be true
      end

      it "finds pages by keywords" do
        get search_path, params: { q: "billing" }, as: :json
        json = JSON.parse(response.body)
        
        expect(json["results"].any? { |r| r["title"] == "Billing" }).to be true
      end

      it "returns page type for navigation results" do
        get search_path, params: { q: "members" }, as: :json
        json = JSON.parse(response.body)
        
        page_results = json["results"].select { |r| r["type"] == "page" }
        expect(page_results).not_to be_empty
      end

      it "returns localized error when search raises" do
        allow_any_instance_of(SearchController).to receive(:perform_search).and_raise(StandardError, "boom")
        get search_path, params: { q: "anything" }, as: :json
        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("controllers.search.search_failed"))
      end

      it "finds My Applications with partial query 'app'" do
        get search_path, params: { q: "app" }, as: :json
        json = JSON.parse(response.body)
        
        titles = json["results"].map { |r| r["title"] }
        expect(titles).to include("My Applications")
      end

      it "finds Apply to Guild" do
        get search_path, params: { q: "apply" }, as: :json
        json = JSON.parse(response.body)
        
        titles = json["results"].map { |r| r["title"] }
        expect(titles).to include("Apply to Guild")
      end

      it "finds Create Guild" do
        get search_path, params: { q: "create" }, as: :json
        json = JSON.parse(response.body)
        
        titles = json["results"].map { |r| r["title"] }
        expect(titles).to include("Create Guild")
      end

      it "finds Contact Support when searching support or help" do
        %w[support help].each do |q|
          get search_path, params: { q: q }, as: :json
          json = JSON.parse(response.body)
          titles = json["results"].map { |r| r["title"] }
          expect(titles).to include("Contact Support"), "expected query '#{q}' to return Contact Support"
        end
      end

      it "returns guild documents from user's guilds when query matches document title" do
        doc = create(:guild_document, guild: guild, user: user, title: "Raid Rules and Guidelines", visibility: :private_doc)
        get search_path, params: { q: "Raid Rules" }, as: :json
        json = JSON.parse(response.body)
        document_results = json["results"].select { |r| r["type"] == "document" }
        expect(document_results.any? { |r| r["title"] == doc.title }).to be true
        expect(document_results.any? { |r| r["guild_id"].to_s == guild.id.to_s }).to be true
      end

      it "does not return documents from guilds the signed-in user is not a member of" do
        other_owner = create(:user)
        other_guild = create(:guild, owner: other_owner)
        secret_title = "IsolationOnlyOtherGuild #{SecureRandom.hex(6)}"
        create(:guild_document, guild: other_guild, user: other_owner, title: secret_title, visibility: :private_doc)

        get search_path, params: { q: secret_title }, as: :json
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        foreign_docs = json["results"].select { |r| r["type"] == "document" && r["title"] == secret_title }
        expect(foreign_docs).to be_empty
      end
    end
  end
end

RSpec.describe SearchIndexService do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }

  describe ".build_document" do
    context "for Event" do
      let(:event) { create(:event, guild: guild, created_by: user, title: "Test Event") }

      it "builds correct document structure" do
        doc = SearchIndexService.send(:build_document, event)

        expect(doc["id"]).to eq("event_#{event.id}")
        expect(doc["type"]).to eq("event")
        expect(doc["guild_id"]).to eq(guild.id.to_s)
        expect(doc["visibility"]).to eq("guild")
        expect(doc["title"]).to eq("Test Event")
        expect(doc["url"]).to include("/guilds/#{guild.id}")
      end
    end

    context "for Poll" do
      let(:poll) { create(:poll, guild: guild, creator: user, title: "Test Poll") }

      it "builds correct document structure" do
        doc = SearchIndexService.send(:build_document, poll)

        expect(doc["id"]).to eq("poll_#{poll.id}")
        expect(doc["type"]).to eq("poll")
        expect(doc["guild_id"]).to eq(guild.id.to_s)
        expect(doc["visibility"]).to eq("guild")
        expect(doc["title"]).to eq("Test Poll")
        expect(doc["url"]).to include("/polls/#{poll.id}")
      end
    end

    context "for GuildDocument" do
      context "public document" do
        let(:document) { create(:guild_document, guild: guild, user: user, title: "Public Doc", visibility: :public_doc) }

        it "sets visibility to public" do
          doc = SearchIndexService.send(:build_document, document)

          expect(doc["visibility"]).to eq("public")
          expect(doc["type"]).to eq("document")
        end
      end

      context "private document" do
        let(:document) { create(:guild_document, guild: guild, user: user, title: "Private Doc", visibility: :private_doc) }

        it "sets visibility to guild" do
          doc = SearchIndexService.send(:build_document, document)

          expect(doc["visibility"]).to eq("guild")
        end
      end
    end

    context "for LootRoll" do
      let(:loot_roll) { create(:loot_roll, guild: guild, creator: user, title: "Test Loot Roll") }

      it "builds correct document structure" do
        doc = SearchIndexService.send(:build_document, loot_roll)

        expect(doc["id"]).to eq("loot_roll_#{loot_roll.id}")
        expect(doc["type"]).to eq("loot_roll")
        expect(doc["guild_id"]).to eq(guild.id.to_s)
        expect(doc["visibility"]).to eq("guild")
        expect(doc["title"]).to eq("Test Loot Roll")
      end
    end
  end

  describe ".build_document_id" do
    let(:event) { create(:event, guild: guild, created_by: user) }

    it "generates unique ID from model name and record ID" do
      id = SearchIndexService.send(:build_document_id, event)
      expect(id).to eq("event_#{event.id}")
    end
  end
end

RSpec.describe SearchController do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }

  before do
    # Ensure guild membership exists for owner
    guild.guild_members.find_or_create_by!(user: user) do |m|
      m.status = :active
      m.role = :owner
    end
    user.update!(auth_method: :discord)
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  describe "#build_permission_filter" do
    let(:controller) { SearchController.new }

    before do
      allow(controller).to receive(:current_user).and_return(user)
      controller.instance_variable_set(:@_request, ActionDispatch::Request.new({}))
    end

    it "includes public visibility filter" do
      filter = controller.send(:build_permission_filter)
      expect(filter).to include("visibility:=public")
    end

    it "includes guild visibility filter for member guilds" do
      filter = controller.send(:build_permission_filter)
      expect(filter).to include("visibility:=guild")
      expect(filter).to include("guild_id:=#{guild.id}")
    end

    it "includes owner_user_id in restricted filter" do
      filter = controller.send(:build_permission_filter)
      expect(filter).to include("owner_user_id:=#{user.id}")
    end

    it "includes allowed_user_ids in restricted filter" do
      filter = controller.send(:build_permission_filter)
      expect(filter).to include("allowed_user_ids:=[#{user.id}]")
    end
  end
end
