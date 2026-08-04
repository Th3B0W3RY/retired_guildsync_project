# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Queries", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  around do |example|
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    example.run
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/queries" do
    it "redirects to admin login when not authenticated" do
      get "/admin/queries"
      expect(response).to redirect_to(admin_login_path)
    end

    it "renders the queries page with translated chrome and saved query labels" do
      post "/admin/login", params: { email: admin_email, password: admin_password }

      get "/admin/queries"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.queries.index.page_title"))
      expect(response.body).to include(I18n.t("admin.queries.index.saved_queries_heading"))
      expect(response.body).to include(I18n.t("admin.queries.saved.active_users_count.name"))
      expect(response.body).to include(I18n.t("admin.queries.saved.active_users_count.description"))
      expect(response.body).to include(I18n.t("admin.queries.index.run"))
    end

    it "returns frame-only HTML when Turbo-Frame targets main index" do
      post "/admin/login", params: { email: admin_email, password: admin_password }

      get "/admin/queries",
        headers: { "Turbo-Frame" => Admin::QueriesController::QUERIES_INDEX_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::QueriesController::QUERIES_INDEX_MAIN_FRAME}"))
      expect(response.body).to include(I18n.t("admin.queries.saved.active_users_count.name"))
      expect(response.body).not_to include(I18n.t("admin.queries.index.page_title"))
    end
  end

  describe "POST /admin/queries/execute" do
    before { post "/admin/login", params: { email: admin_email, password: admin_password } }

    it "redirects with alert when no query is selected" do
      post "/admin/queries/execute"
      expect(response).to redirect_to(admin_queries_path)
      expect(flash[:alert]).to eq(I18n.t("admin.queries.invalid_selection"))
    end

    it "renders index with translated error when custom query is not SELECT" do
      post "/admin/queries/execute", params: { custom_query: "UPDATE users SET id = id" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.queries.index.query_error_heading"))
      msg = I18n.t("admin.queries.execution_error", message: I18n.t("admin.queries.errors.only_select_allowed"))
      expect(response.body).to include(ERB::Util.html_escape(msg))
    end

    it "renders index with translated error when custom query contains a prohibited keyword" do
      post "/admin/queries/execute", params: { custom_query: "SELECT id FROM users; DELETE FROM users" }
      expect(response).to have_http_status(:success)
      msg = I18n.t("admin.queries.execution_error", message: I18n.t("admin.queries.errors.prohibited_keywords"))
      expect(response.body).to include(ERB::Util.html_escape(msg))
    end

    it "runs a saved count query and shows the numeric result" do
      count_row = double(values: [ 42 ])
      result = double(first: count_row)
      allow(ActiveRecord::Base.connection).to receive(:execute).and_return(result)

      post "/admin/queries/execute", params: { query_key: "active_users_count" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("42")
      expect(response.body).to include(I18n.t("admin.queries.saved.active_users_count.name"))
    end

    it "runs a saved results query and shows row count copy" do
      rows = [ { "plan_name" => "Basic", "user_count" => 3 } ]
      allow(ActiveRecord::Base.connection).to receive(:execute).and_return(rows)

      post "/admin/queries/execute", params: { query_key: "users_by_plan" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Basic")
      expect(response.body).to include(I18n.t("admin.queries.index.row_count", count: 1))
    end

    it "returns turbo_stream replacing results wrap for saved count query" do
      count_row = double(values: [ 99 ])
      result = double(first: count_row)
      allow(ActiveRecord::Base.connection).to receive(:execute).and_return(result)

      post "/admin/queries/execute",
        params: { query_key: "active_users_count" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_queries_results_wrap")
      expect(response.body).to include("99")
    end

    it "returns see_other to queries index when nothing selected and Accept is turbo_stream" do
      post "/admin/queries/execute", headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to include(admin_queries_path)
    end

    it "returns turbo_stream with execution error for invalid custom SQL" do
      post "/admin/queries/execute",
        params: { custom_query: "UPDATE users SET id = id" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include("admin_queries_results_wrap")
      msg = I18n.t("admin.queries.execution_error", message: I18n.t("admin.queries.errors.only_select_allowed"))
      expect(response.body).to include(ERB::Util.html_escape(msg))
    end
  end
end
