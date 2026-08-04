# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Password new (account recovery page)", type: :request do
  describe "GET /password/new" do
    it "renders email reset and backup code sections and admin-configured support pages link" do
      get new_password_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email-reset-form")
      expect(response.body).to include(%(action="#{password_path}"))
      expect(response.body).to include('name="user[email]"')
      expect(response.body).to include("password_reset_email")
      expect(response.body).to include("backup-code-form")
      expect(response.body).to include(%(action="#{verify_backup_codes_path}"))
      expect(response.body).to include(%(href="#{release_notes_path}"))
      expect(response.body).not_to include(%(href="#{footer_support_contact_path}"))
      expect(response.body).not_to include("guildsyncsupport.zohodesk.com")

      doc = Nokogiri::HTML(response.body)
      email_form = doc.at_css("form.email-reset-form")
      expect(email_form["data-turbo"]).to eq("false")
      backup_form = doc.at_css("form.backup-code-form")
      expect(backup_form["data-turbo"]).to eq("false")
    end

    it "routes Contact Support through the current admin-configured support pages URL" do
      SiteSetting.set("release_notes_url", "https://password-recovery-support.example/help")

      get new_password_path

      doc = Nokogiri::HTML(response.body)
      contact_support_href = doc.at_css(%(a[href="#{release_notes_path}"]))["href"]

      get contact_support_href

      expect(response).to redirect_to("https://password-recovery-support.example/help")
    end
  end
end
