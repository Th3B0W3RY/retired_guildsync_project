# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::FeatureFlags (removed)", type: :request do
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

  it "returns 404 when accessing removed feature_flags path" do
    get "/admin/feature_flags"
    expect(response).to have_http_status(:not_found)
  end
end
