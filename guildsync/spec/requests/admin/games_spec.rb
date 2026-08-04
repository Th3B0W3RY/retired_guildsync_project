# frozen_string_literal: true

require "erb"
require 'rails_helper'

RSpec.describe "Admin::Games", type: :request do
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

  describe "GET /admin/games/pending" do
    let!(:pending_game) { create(:game, active: false, deactivated_at: nil) }
    let!(:active_game) { create(:game, active: true) }

    it "lists pending games" do
      get "/admin/games/pending"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(pending_game.name)
      expect(response.body).not_to include(active_game.name)
      expect(response.body).to include(I18n.t("admin.games.pending.page_title"))
    end

    it "returns frame-only HTML when Turbo-Frame targets pending main" do
      get "/admin/games/pending",
        headers: { "Turbo-Frame" => Admin::GamesController::GAMES_PENDING_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::GamesController::GAMES_PENDING_MAIN_FRAME}"))
      expect(response.body).to include(pending_game.name)
      expect(response.body).not_to include(I18n.t("admin.games.pending.page_title"))
    end
  end

  describe "POST /admin/games/:id/approve" do
    let!(:pending_game) { create(:game, active: false, deactivated_at: nil) }

    it "approves a pending game" do
      expect(pending_game.active?).to be false

      post "/admin/games/#{pending_game.id}/approve"

      expect(response).to redirect_to(pending_games_admin_games_path)
      expect(flash[:notice]).to eq(I18n.t("admin.games.flash.approved", name: pending_game.name))
      pending_game.reload
      expect(pending_game.active?).to be true
      expect(pending_game.deactivated_at).to be_nil
    end

    it "returns turbo-stream remove and flash when another pending remains" do
      create(:game, active: false, deactivated_at: nil, name: "Other Pending")
      post "/admin/games/#{pending_game.id}/approve", headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="remove"', "admin_pending_game_row_#{pending_game.id}")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.games.flash.approved", name: pending_game.name))
      )
      pending_game.reload
      expect(pending_game.active?).to be true
    end

    it "returns turbo-stream replace with empty state when last pending is approved" do
      post "/admin/games/#{pending_game.id}/approve", headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"', "admin_games_pending_content")
      expect(response.body).to include(I18n.t("admin.games.pending.empty"))
      pending_game.reload
      expect(pending_game.active?).to be true
    end

    it "returns turbo-stream flash alert on approve failure" do
      allow(Game).to receive(:find).with(pending_game.id.to_s).and_return(pending_game)
      allow(pending_game).to receive(:update).and_return(false)
      errs = ActiveModel::Errors.new(pending_game)
      errs.add(:base, "fail")
      allow(pending_game).to receive(:errors).and_return(errs)

      post "/admin/games/#{pending_game.id}/approve", headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update"', "admin_games_pending_flash")
      expect(response.body).to include(I18n.t("admin.games.flash.approve_failed", errors: "fail"))
    end
  end

  describe "POST /admin/games/:id/deny" do
    let!(:pending_game) { create(:game, active: false, deactivated_at: nil) }

    it "denies a pending game" do
      expect(pending_game.deactivated_at).to be_nil
      game_name = pending_game.name

      post "/admin/games/#{pending_game.id}/deny"

      expect(response).to redirect_to(pending_games_admin_games_path)
      expect(flash[:notice]).to eq(I18n.t("admin.games.flash.denied", name: game_name))
      pending_game.reload
      expect(pending_game.deactivated_at).not_to be_nil
      expect(pending_game.deactivation_reason).to include("Denied by admin")
    end

    it "returns turbo-stream remove and flash when another pending remains" do
      create(:game, active: false, deactivated_at: nil, name: "Other Pending")
      post "/admin/games/#{pending_game.id}/deny", headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="remove"', "admin_pending_game_row_#{pending_game.id}")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.games.flash.denied", name: pending_game.name))
      )
    end

    it "returns turbo-stream replace with empty state when last pending is denied" do
      post "/admin/games/#{pending_game.id}/deny", headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"', "admin_games_pending_content")
      expect(response.body).to include(I18n.t("admin.games.pending.empty"))
    end
  end

  describe "DELETE /admin/games/:id/reject" do
    let!(:pending_game) { create(:game, active: false, deactivated_at: nil) }

    it "rejects and deletes a pending game" do
      game_id = pending_game.id
      game_name = pending_game.name
      expect(Game.find_by(id: game_id)).to be_present

      delete "/admin/games/#{pending_game.id}/reject"

      expect(response).to redirect_to(pending_games_admin_games_path)
      expect(flash[:notice]).to eq(I18n.t("admin.games.flash.rejected", name: game_name))
      expect(Game.find_by(id: game_id)).to be_nil
    end

    it "returns turbo-stream remove and flash when another pending remains" do
      other = create(:game, active: false, deactivated_at: nil, name: "Other Pending")
      delete "/admin/games/#{pending_game.id}/reject", headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="remove"', "admin_pending_game_row_#{pending_game.id}")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.games.flash.rejected", name: pending_game.name))
      )
      expect(Game.find_by(id: pending_game.id)).to be_nil
      expect(other.reload).to be_present
    end

    it "returns turbo-stream replace with empty state when last pending is rejected" do
      game_name = pending_game.name
      delete "/admin/games/#{pending_game.id}/reject", headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"', "admin_games_pending_content")
      expect(response.body).to include(I18n.t("admin.games.pending.empty"))
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.games.flash.rejected", name: game_name))
      )
    end
  end

  describe "GET /admin/games" do
    let!(:active_game1) { create(:game, name: "Game One", active: true) }
    let!(:active_game2) { create(:game, name: "Game Two", active: true) }
    let!(:pending_game) { create(:game, active: false) }

    it "lists all active cached games" do
      get "/admin/games"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(active_game1.name)
      expect(response.body).to include(active_game2.name)
      expect(response.body).not_to include(pending_game.name)
      expect(response.body).to include(I18n.t("admin.games.index.page_title"))
    end

    it "searches games by name" do
      get "/admin/games", params: { q: "One" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(active_game1.name)
      expect(response.body).not_to include(active_game2.name)
    end

    it "returns frame-only HTML when Turbo-Frame targets results" do
      get "/admin/games",
        params: { q: "One" },
        headers: { "Turbo-Frame" => Admin::GamesController::GAMES_INDEX_RESULTS_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::GamesController::GAMES_INDEX_RESULTS_FRAME}"))
      expect(response.body).to include(active_game1.name)
      expect(response.body).not_to include(active_game2.name)
      expect(response.body).not_to include(I18n.t("admin.games.index.page_title"))
    end
  end

  describe "GET /admin/games/search" do
    let!(:game1) { create(:game, name: "Test Game One", active: true, description: "First test game") }
    let!(:game2) { create(:game, name: "Test Game Two", active: true, description: "Second test game") }
    let!(:inactive_game) { create(:game, name: "Inactive Game", active: false) }

    it "returns JSON with game suggestions" do
      get "/admin/games/search", params: { q: "Test" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")
      
      json = JSON.parse(response.body)
      expect(json).to have_key("games")
      expect(json["games"].length).to be > 0
      expect(json["games"].first).to have_key("id")
      expect(json["games"].first).to have_key("name")
    end

    it "only returns active games" do
      get "/admin/games/search", params: { q: "Game" }
      json = JSON.parse(response.body)
      game_names = json["games"].map { |g| g["name"] }
      expect(game_names).to include(game1.name)
      expect(game_names).to include(game2.name)
      expect(game_names).not_to include(inactive_game.name)
    end

    it "returns empty array for blank query" do
      get "/admin/games/search", params: { q: "" }
      json = JSON.parse(response.body)
      expect(json["games"]).to eq([])
    end

    it "searches by game name" do
      get "/admin/games/search", params: { q: "One" }
      json = JSON.parse(response.body)
      expect(json["games"].any? { |g| g["name"] == "Test Game One" }).to be true
    end

    it "limits results to 10" do
      15.times { |i| create(:game, name: "Game #{i}", active: true) }
      get "/admin/games/search", params: { q: "Game" }
      json = JSON.parse(response.body)
      expect(json["games"].length).to be <= 10
    end
  end

  describe "DELETE /admin/games/:id" do
    let!(:active_game) { create(:game, active: true) }

    it "deletes a cached game" do
      game_id = active_game.id
      game_name = active_game.name
      expect(Game.find_by(id: game_id)).to be_present

      delete "/admin/games/#{active_game.id}"

      expect(response).to redirect_to(admin_games_path)
      expect(flash[:notice]).to eq(I18n.t("admin.games.flash.deleted_from_cache", name: game_name))
      expect(Game.find_by(id: game_id)).to be_nil
    end
  end
end

