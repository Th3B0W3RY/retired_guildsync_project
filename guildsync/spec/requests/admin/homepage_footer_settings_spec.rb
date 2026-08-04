# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin homepage footer settings", type: :request do
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

  describe "GET /admin/homepage-footer" do
    it "renders the footer settings page with legal page links" do
      get admin_homepage_footer_settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Homepage Footer Links & Legal Pages")
      expect(response.body).to include("Documentation URL")
      expect(response.body).to include("Privacy")
      expect(response.body).to include(edit_admin_marketing_legal_page_path("privacy"))
      expect(response.body).to include(edit_admin_marketing_legal_page_path("disaster_recovery"))
      expect(response.body).to include("Disaster Recovery")
    end
  end

  describe "PATCH /admin/homepage-footer" do
    let(:params) do
      {
        homepage_footer: {
          documentation_url: "https://docs.example.test",
          contact_url: "https://contact.example.test",
          discord_url: "https://discord.gg/guildsync"
        }
      }
    end

    it "updates the footer support links in SiteSetting" do
      patch admin_update_homepage_footer_settings_path, params: params

      expect(response).to redirect_to(admin_homepage_footer_settings_path)
      expect(SiteSetting.homepage_footer_documentation_url).to eq("https://docs.example.test")
      expect(SiteSetting.homepage_footer_contact_url).to eq("https://contact.example.test")
      expect(SiteSetting.homepage_footer_discord_url).to eq("https://discord.gg/guildsync")
    end

    it "creates an audit log entry" do
      expect {
        patch admin_update_homepage_footer_settings_path, params: params
      }.to change(AdminAuditLog, :count).by(1)

      expect(AdminAuditLog.last.action).to eq("update_homepage_footer_support_links")
    end

    it "rejects invalid urls" do
      patch admin_update_homepage_footer_settings_path, params: {
        homepage_footer: {
          documentation_url: "ftp://bad.example",
          contact_url: "https://contact.example.test",
          discord_url: "https://discord.gg/guildsync"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Documentation URL must be a valid URL.")
    end

    it "rejects malformed HTTP urls before saving footer support links" do
      SiteSetting.set("homepage_footer_documentation_url", "https://existing-docs.example.test")

      expect {
        patch admin_update_homepage_footer_settings_path, params: {
          homepage_footer: {
            documentation_url: "https:///missing-host",
            contact_url: "https://contact.example.test",
            discord_url: "https://discord.gg/guildsync"
          }
        }
      }.not_to change { SiteSetting.homepage_footer_documentation_url }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Documentation URL must be a valid URL.")
    end
  end

  describe "PATCH /admin/marketing-legal-pages/:id" do
    it "renders the legal page editor with the custom rich text toolbar" do
      get edit_admin_marketing_legal_page_path("privacy")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-controller="editor"')
      expect(response.body).to include('data-editor-target="editor"')
      expect(response.body).to include('name="marketing_legal_page[body]"')
    end

    it "updates a legal page title and body" do
      page = MarketingLegalPage.for_kind!("privacy")

      patch admin_marketing_legal_page_path(page.kind), params: {
        marketing_legal_page: {
          title: "Updated Privacy Policy",
          body: "<div>Updated body copy</div>"
        }
      }

      expect(response).to redirect_to(admin_homepage_footer_settings_path)
      expect(page.reload.title).to eq("Updated Privacy Policy")
      expect(page.body.to_plain_text).to include("Updated body copy")
      expect(AdminAuditLog.last.action).to eq("update_marketing_legal_page")
    end
  end
end
