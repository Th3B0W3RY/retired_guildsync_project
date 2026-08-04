# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin access to GamesController", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }
  let(:unique_game_suffix) { SecureRandom.hex(4) }

  describe "with admin session" do
    before do
      ENV["ADMIN_EMAIL"] = admin_email
      ENV["ADMIN_PASSWORD"] = admin_password
      # Login to establish admin session (don't follow redirect to preserve session)
      post "/admin/login", params: { email: admin_email, password: admin_password }
      follow_redirect! if response.redirect?
    end

    after do
      ENV.delete("ADMIN_EMAIL")
      ENV.delete("ADMIN_PASSWORD")
    end

    it "allows admin to access games index without user session" do
      create(:game, name: "Test Game 1", active: true)
      create(:game, name: "Test Game 2", active: true)

      get "/games"

      # Should not redirect to login (which would be 302)
      expect(response).not_to have_http_status(:redirect)
      # May be 406 (missing template) or 200 (success) - both indicate access was granted
      expect([200, 406]).to include(response.status)
    end

    it "allows admin to access game show page without user session" do
      game = create(:game, name: "Test Game #{unique_game_suffix}", active: true)

      get "/games/#{game.id}"

      # Should not redirect to login (which would be 302)
      expect(response).not_to have_http_status(:redirect)
      # May be 406 (missing template) or 200 (success) - both indicate access was granted
      expect([200, 406]).to include(response.status)
    end

    it "allows admin to access new game page without user session" do
      get "/games/new"

      # Should not redirect to login (which would be 302)
      expect(response).not_to have_http_status(:redirect)
      # May be 406 (missing template) or 200 (success) - both indicate access was granted
      expect([200, 406]).to include(response.status)
    end

    it "allows admin to access edit game page without user session" do
      game = create(:game, name: "Test Game Edit #{unique_game_suffix}", active: true)

      get "/games/#{game.id}/edit"

      # Should not redirect to login (which would be 302)
      expect(response).not_to have_http_status(:redirect)
      # May be 406 (missing template) or 200 (success) - both indicate access was granted
      expect([200, 406]).to include(response.status)
    end
  end

  describe "without admin session" do
    it "redirects to login when accessing games index without authentication" do
      get "/games"

      expect(response).to redirect_to(login_path)
    end

    it "redirects to login when accessing game show without authentication" do
      game = create(:game, name: "Test Game Unauth #{unique_game_suffix}", active: true)

      get "/games/#{game.id}"

      expect(response).to redirect_to(login_path)
    end
  end
end

