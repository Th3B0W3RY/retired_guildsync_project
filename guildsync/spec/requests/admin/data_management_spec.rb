# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::DataManagement (removed)", type: :request do
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

  it "returns 404 when posting to removed delete_all path" do
    post "/admin/data/delete_all", params: { confirmation: "YES I AM SURE" }
    expect(response).to have_http_status(:not_found)
  end
end
