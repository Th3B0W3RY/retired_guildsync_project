# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Sidekiq Access", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /sidekiq" do
    context "when admin is authenticated" do
      before do
        post "/admin/login", params: { email: admin_email, password: admin_password }
      end

      it "allows access to Sidekiq web UI" do
        get "/sidekiq"
        # Sidekiq returns 200 or redirects to a specific page
        expect(response).to have_http_status(:success).or have_http_status(:redirect)
      end
    end

    context "when admin is not authenticated" do
      it "redirects to admin login page" do
        get "/sidekiq"
        expect(response).to redirect_to(admin_login_path)
      end
    end

    context "when regular user is logged in" do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it "redirects to admin login page" do
        get "/sidekiq"
        expect(response).to redirect_to(admin_login_path)
      end
    end
  end
end

