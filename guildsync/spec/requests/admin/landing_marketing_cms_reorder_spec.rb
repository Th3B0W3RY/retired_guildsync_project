# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin landing marketing CMS reorder integrity", type: :request do
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

  describe "guest access" do
    it "redirects feedback reorder to login and preserves order" do
      delete "/admin/logout"
      a = create(:landing_user_feedback, position: 0)
      b = create(:landing_user_feedback, position: 1)

      patch "/admin/landing-user-feedbacks/reorder", params: { order: [ b.id, a.id ] }

      expect(response).to redirect_to(admin_login_path)
      expect(a.reload.position).to eq(0)
      expect(b.reload.position).to eq(1)
    end

    it "redirects feature card reorder to login and preserves order" do
      delete "/admin/logout"
      a = create(:homepage_feature_card, position: 0)
      b = create(:homepage_feature_card, position: 1)

      patch "/admin/homepage-feature-cards/reorder", params: { order: [ b.id, a.id ] }

      expect(response).to redirect_to(admin_login_path)
      expect(a.reload.position).to eq(0)
      expect(b.reload.position).to eq(1)
    end
  end

  it "rejects landing feedback reorder payloads that omit records" do
    a = create(:landing_user_feedback, position: 0)
    b = create(:landing_user_feedback, position: 1)

    patch "/admin/landing-user-feedbacks/reorder", params: { order: [a.id] }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(a.reload.position).to eq(0)
    expect(b.reload.position).to eq(1)
  end

  it "rejects feature card reorder payloads that include unknown ids" do
    a = create(:homepage_feature_card, position: 0)
    b = create(:homepage_feature_card, position: 1)

    patch "/admin/homepage-feature-cards/reorder", params: { order: [a.id, b.id, 999_999] }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(a.reload.position).to eq(0)
    expect(b.reload.position).to eq(1)
  end
end
