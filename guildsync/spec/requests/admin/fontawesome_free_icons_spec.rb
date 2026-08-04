# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Font Awesome free icons JSON", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  it "redirects guests" do
    get admin_fontawesome_free_icons_path, headers: { "Accept" => "application/json" }

    expect(response).to redirect_to(admin_login_path)
  end

  it "returns ordered icon tuples for admins" do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }

    create(:fontawesome_free_icon, style: "brands", icon_name: "github", label: "GitHub")
    create(:fontawesome_free_icon, style: "solid", icon_name: "key", label: "Key")

    get admin_fontawesome_free_icons_path, headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body["icons"]).to eq([
      [ "brands", "github", "GitHub" ],
      [ "solid", "key", "Key" ]
    ])
  ensure
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end
end
