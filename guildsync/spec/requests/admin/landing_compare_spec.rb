# frozen_string_literal: true

require "rails_helper"
require "erb"

RSpec.describe "Admin::LandingCompare", type: :request do
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

  def payload_from_database(section_title: "")
    tables = {}
    LandingComparisonTable.order(:position).each do |t|
      rows = {}
      t.landing_comparison_rows.order(:position).each do |r|
        rows[r.position.to_s] = {
          "feature_label" => r.feature_label,
          "guildsync_included" => r.guildsync_included ? "1" : "0",
          "competitor_included" => r.competitor_included ? "1" : "0"
        }
      end
      tables[t.position.to_s] = {
        "feature_column_label" => t.feature_column_label,
        "guildsync_column_label" => t.guildsync_column_label,
        "competitor_column_label" => t.competitor_column_label,
        "show_guildsync_badge" => t.show_guildsync_badge ? "1" : "0",
        "rows" => rows
      }
    end
    { landing_compare: { section_title: section_title, tables: tables } }
  end

  describe "GET /admin/landing-compare" do
    it "creates default comparison tables when the database has none (DB CMS bootstrap)" do
      LandingComparisonRow.delete_all
      LandingComparisonTable.delete_all
      expect(LandingComparisonTable.count).to eq(0)

      get "/admin/landing-compare"

      expect(response).to have_http_status(:success)
      expect(LandingComparisonTable.count).to eq(3)
      expect(LandingComparisonTable.order(:position).pluck(:position)).to eq([ 0, 1, 2 ])
      tables = LandingComparisonTable.order(:position).to_a
      expect(tables.all? { |table| table.landing_comparison_rows.exists? }).to be(true)
      expect(response.body).not_to include(I18n.t("admin.landing_compare.incomplete_tables_warning"))
    end

    it "renders edit form when three tables exist" do
      get "/admin/landing-compare"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.landing_compare.page_title"))
      expect(response.body).to include("landing_compare[section_title]")
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      get "/admin/landing-compare",
        headers: { "Turbo-Frame" => Admin::LandingCompareController::LANDING_COMPARE_EDIT_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_landing_compare_main"))
      expect(response.body).to include("landing_compare[section_title]")
      expect(response.body).not_to include(I18n.t("admin.landing_compare.page_title"))
    end
  end

  describe "PATCH /admin/landing-compare" do
    it "updates section title and a row label" do
      table0 = LandingComparisonTable.find_by!(position: 0)
      first_pos = table0.landing_comparison_rows.order(:position).first.position

      params = payload_from_database(section_title: "Custom Section Heading")
      params[:landing_compare][:tables]["0"]["rows"][first_pos.to_s]["feature_label"] = "Edited Feature Alpha"

      patch "/admin/landing-compare", params: params

      expect(response).to redirect_to(admin_edit_landing_compare_path)
      expect(flash[:notice]).to eq(I18n.t("admin.landing_compare.updated"))
      expect(SiteSetting.get("landing_compare_section_title")).to eq("Custom Section Heading")
      expect(table0.landing_comparison_rows.order(:position).first.feature_label).to eq("Edited Feature Alpha")
    end

    it "returns turbo_stream refresh on successful save" do
      table0 = LandingComparisonTable.find_by!(position: 0)
      first_pos = table0.landing_comparison_rows.order(:position).first.position

      params = payload_from_database(section_title: "Turbo Section Title")
      params[:landing_compare][:tables]["0"]["rows"][first_pos.to_s]["feature_label"] = "Turbo Row Label"

      patch "/admin/landing-compare",
        params: params,
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="update"', "admin_landing_compare_flash")
      expect(response.body).to include('action="replace"', "admin_landing_compare_form_wrap")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.landing_compare.updated"))
      )
      expect(response.body).to include("Turbo Section Title")
      expect(response.body).to include("Turbo Row Label")
      expect(SiteSetting.get("landing_compare_section_title")).to eq("Turbo Section Title")
      expect(table0.landing_comparison_rows.order(:position).first.reload.feature_label).to eq("Turbo Row Label")
    end

    it "rejects unauthenticated access" do
      delete "/admin/logout"
      patch "/admin/landing-compare", params: payload_from_database

      expect(response).to redirect_to(admin_login_path)
    end
  end
end
