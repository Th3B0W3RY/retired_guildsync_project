# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Roadmap (feature requests)", type: :request do
  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:valid_title) { "Add dark mode support" }
  let(:valid_description) { "A clear description that is at least fifty characters long for validation." }
  let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

  describe "GET /roadmap" do
    it "returns success and is public (no sign-in required)" do
      get roadmap_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Roadmap", "Feature")
    end

    it "matches Figma 56:772 guest roadmap (no release-notes block; footer + Upcoming subtitle)" do
      get roadmap_path
      expect(response.body).to include(I18n.t("roadmap.guest_footer_note"))
      expect(response.body).to include(I18n.t("roadmap.subtitle"))
      expect(response.body).not_to include(I18n.t("layouts.application.dropdown.release_notes_instructions"))
    end

    it "guest roadmap Figma chrome matches on mobile HTML variant (marketing shell, not member dropdown)" do
      get roadmap_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("roadmap.guest_footer_note"))
      expect(response.body).to include(I18n.t("roadmap.subtitle"))
      expect(response.body).not_to include(I18n.t("layouts.application.dropdown.release_notes_instructions"))
    end

    it "signed-in roadmap: tablist sits above column lists (hint card removed); omits dropdown release-notes path copy" do
      sign_in user
      set_mfa_verified_in_session
      get roadmap_path
      body = response.body
      tab_ix = body.index('role="tablist"')
      col_ix = body.index("roadmap_column_list_considering")
      expect(tab_ix).to be_a(Integer)
      expect(col_ix).to be_a(Integer)
      expect(tab_ix).to be < col_ix
      expect(body).to include(I18n.t("roadmap.columns.popular"))
      expect(body).to include(I18n.t("roadmap.create_button"))
      expect(body).not_to include(I18n.t("layouts.application.dropdown.release_notes_instructions"))
    end

    it "signed-in roadmap on mobile variant: tablist before columns; omits dropdown release-notes path copy" do
      sign_in user
      set_mfa_verified_in_session
      get roadmap_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      body = response.body
      tab_ix = body.index('role="tablist"')
      col_ix = body.index("roadmap_column_list_considering")
      expect(tab_ix).to be_a(Integer)
      expect(col_ix).to be_a(Integer)
      expect(tab_ix).to be < col_ix
      expect(body).to include(I18n.t("roadmap.create_button"))
      expect(body).not_to include(I18n.t("layouts.application.dropdown.release_notes_instructions"))
    end

    context "signed-in support_center_url still present in HTML (e.g. layout chrome)" do
      before do
        sign_in user
        set_mfa_verified_in_session
      end

      it "includes default support URL in HTML" do
        get roadmap_path
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get roadmap_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://roadmap-signed-in-support.example/help")
        get roadmap_path
        expect(response.body).to include("https://roadmap-signed-in-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://roadmap-signed-in-support.example/help")
        get roadmap_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://roadmap-signed-in-support.example/help")
      end
    end

    it "renders a Popular column for requests with more than 15 votes" do
      popular_fr = create(:feature_request, user: user, vote_count: 20, status: "considering")
      unpopular_fr = create(:feature_request, user: user, vote_count: 5, status: "considering")

      get roadmap_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Popular")
      expect(response.body).to include(popular_fr.title)
    end
  end

  describe "POST /roadmap/requests (create feature request)" do
    context "when not signed in" do
      it "returns 401 for JSON and does not create a feature request" do
        expect {
          post roadmap_requests_path, params: { feature_request: { title: valid_title, description: valid_description } }, as: :json
        }.not_to change(FeatureRequest, :count)
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to have_key("error")
      end

      it "redirects when not signed in for HTML (Devise sends to root)" do
        post roadmap_requests_path, params: { feature_request: { title: valid_title, description: valid_description } }
        expect(response).to have_http_status(:redirect)
        expect(response.location).to end_with("/")
      end
    end

    context "when signed in" do
      before do
        sign_in user
        set_mfa_verified_in_session
      end

      it "creates a feature request with valid params" do
        expect {
          post roadmap_requests_path, params: { feature_request: { title: valid_title, description: valid_description } }, as: :json
        }.to change(FeatureRequest, :count).by(1)
        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json).to have_key("id")
        expect(FeatureRequest.find(json["id"]).user_id).to eq(user.id)
      end

      it "creates request but with moderation_status pending when title contains blocked content" do
        post roadmap_requests_path, params: {
          feature_request: { title: "This contains blockedterm", description: valid_description }
        }, as: :json
        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json).to have_key("id")
        expect(json["moderation_status"]).to eq("pending")
        expect(FeatureRequest.find(json["id"]).moderation_status).to eq("pending")
      end

      it "creates request with moderation pending when title hits severe blocklist without profanity" do
        post roadmap_requests_path, params: {
          feature_request: { title: "Discussion about nazi imagery in games", description: valid_description }
        }, as: :json
        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["moderation_status"]).to eq("pending")
        fr = FeatureRequest.find(json["id"])
        expect(fr.moderation_triggered_words_list).to include("nazi")
      end

      it "returns 422 when description is too short" do
        post roadmap_requests_path, params: {
          feature_request: { title: valid_title, description: "Too short" }
        }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
      end

      it "returns turbo-stream that appends to the considering column when submission is approved" do
        expect {
          post roadmap_requests_path,
               params: { feature_request: { title: valid_title, description: valid_description } },
               headers: { "Accept" => Mime[:turbo_stream].to_s }
        }.to change(FeatureRequest, :count).by(1)
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq(Mime[:turbo_stream])
        expect(response.body).to include('action="append"', "roadmap_column_list_considering")
        expect(response.body).to include(valid_title)
      end

      it "returns turbo-stream without appending when search q does not match the new request" do
        post roadmap_requests_path,
             params: {
               q: "xyznonexistentterm",
               feature_request: { title: valid_title, description: valid_description }
             },
             headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('action="append"')
        expect(response.body).to include(I18n.t("roadmap.create.filtered_board_hint"))
      end

      it "returns 422 turbo-stream for invalid feature request" do
        post roadmap_requests_path,
             params: { feature_request: { title: valid_title, description: "Too short" } },
             headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("roadmap_modal_form_errors")
      end

      it "returns turbo-stream moderation notice without append when title triggers pending moderation" do
        post roadmap_requests_path,
             params: {
               feature_request: { title: "This contains blockedterm", description: valid_description }
             },
             headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("roadmap.create.sent_for_review"))
        expect(response.body).not_to include('action="append"')
      end
    end
  end

  describe "POST /roadmap/requests/:id/comments (moderation)" do
    let(:feature_request) { create(:feature_request, user: user) }

    it "returns 401 when not signed in" do
      post roadmap_request_comments_path(feature_request), params: { body: "Hello" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "when signed in" do
      before do
        sign_in user
        set_mfa_verified_in_session
      end

      it "creates comment with moderation_status pending when body contains blocked content" do
        expect {
          post roadmap_request_comments_path(feature_request), params: { body: "This contains blockedterm" }, as: :json
        }.to change(FeatureRequestComment, :count).by(1)
        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["moderation_status"]).to eq("pending")
        expect(FeatureRequestComment.last.moderation_triggered_words_list).to include("blockedterm")
      end

      it "creates approved comment when body is clean" do
        post roadmap_request_comments_path(feature_request), params: { body: "Thanks for the roadmap update" }, as: :json
        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["moderation_status"]).to eq("approved")
      end

      it "creates comment pending when body hits severe blocklist without profanity" do
        body = "Historical context mentioning hitler requires moderation review here."
        post roadmap_request_comments_path(feature_request), params: { body: body }, as: :json
        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["moderation_status"]).to eq("pending")
        expect(FeatureRequestComment.last.moderation_triggered_words_list).to include("hitler")
      end

      it "returns turbo-stream append for approved comment (does not leak pending body in stream)" do
        clean = "Thanks for the turbo stream slice"
        post roadmap_request_comments_path(feature_request),
             params: { body: clean },
             headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq(Mime[:turbo_stream])
        expect(response.body).to include('action="append"', "roadmap_comments_list")
        expect(response.body).to include(clean)
        expect(response.body).to include('target="roadmap_comments_count"')
      end

      it "returns turbo-stream moderation notice without appending pending comment HTML" do
        post roadmap_request_comments_path(feature_request),
             params: { body: "This contains blockedterm" },
             headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("roadmap_comment_moderation_notice")
        expect(response.body).to include(I18n.t("roadmap.comments.sent_for_review"))
        expect(response.body).not_to include("This contains blockedterm")
      end

      it "returns 422 turbo-stream for empty body" do
        post roadmap_request_comments_path(feature_request),
             params: { body: "" },
             headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.media_type).to eq(Mime[:turbo_stream])
        expect(response.body).to include("roadmap_comment_form_errors")
        expect(response.body).to include(I18n.t("roadmap.comments.empty"))
      end
    end
  end

  describe "GET /roadmap/:id (show)" do
    it "returns localized JSON not found when no public feature request matches id" do
      get roadmap_feature_request_path(9_999_999), as: :json
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq(I18n.t("roadmap.not_found"))
    end
  end

  describe "GET /roadmap/:id support_center_url in member chrome when signed in" do
    let(:feature_request) { create(:feature_request, user: user) }

    before do
      sign_in user
      set_mfa_verified_in_session
    end

    it "includes default support URL in HTML" do
      get roadmap_feature_request_path(feature_request)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get roadmap_feature_request_path(feature_request), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://roadmap-show-signed-in-support.example/help")
      get roadmap_feature_request_path(feature_request)
      expect(response.body).to include("https://roadmap-show-signed-in-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://roadmap-show-signed-in-support.example/help")
      get roadmap_feature_request_path(feature_request), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://roadmap-show-signed-in-support.example/help")
    end
  end

  describe "GET /roadmap/:id (public comments)" do
    let(:author) do
      u = create(:user)
      u.update!(auth_method: "discord")
      u
    end
    let(:feature_request) { create(:feature_request, user: user) }

    it "shows only approved comments, not pending moderated ones" do
      create(:feature_request_comment, feature_request: feature_request, user: author, body: "Visible approved note")
      create(:feature_request_comment, feature_request: feature_request, user: author, body: "This contains blockedterm and is hidden")

      expect(feature_request.feature_request_comments.find_by(body: "Visible approved note").moderation_status).to eq("approved")
      hidden = feature_request.feature_request_comments.find_by(body: "This contains blockedterm and is hidden")
      expect(hidden.moderation_status).to eq("pending")

      get roadmap_feature_request_path(feature_request)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Visible approved note")
      expect(response.body).not_to include("This contains blockedterm and is hidden")
    end
  end

  describe "POST /roadmap/requests/:id/vote (JSON)" do
    it "returns 401 JSON when not signed in (Devise runs before controller)" do
      post roadmap_request_vote_path(9_999_999), as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to have_key("error")
    end

    it "returns localized not found when no public feature request matches id" do
      sign_in user
      post roadmap_request_vote_path(9_999_999), as: :json
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq(I18n.t("roadmap.vote.not_found"))
    end

    it "toggles vote and returns vote_count when request is visible to the public" do
      fr = create(:feature_request, user: user, vote_count: 3)
      sign_in user
      post roadmap_request_vote_path(fr), as: :json
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["voted"]).to eq(true)
      expect(body["vote_count"]).to eq(4)
      post roadmap_request_vote_path(fr), as: :json
      expect(response).to have_http_status(:success)
      body2 = JSON.parse(response.body)
      expect(body2["voted"]).to eq(false)
      expect(body2["vote_count"]).to eq(3)
    end
  end

  describe "DELETE /roadmap/comments/:id" do
    let(:comment_author) do
      u = create(:user)
      u.update!(auth_method: "discord")
      u
    end
    let(:fr_for_comment) { create(:feature_request, user: comment_author) }
    let(:approved_comment_body) { "A helpful public comment with enough text for clarity and moderation." }

    it "returns 401 JSON when not signed in" do
      comment = create(:feature_request_comment, feature_request: fr_for_comment, user: comment_author, body: approved_comment_body)
      expect(comment.reload.moderation_status).to eq("approved")
      delete roadmap_comment_path(comment), as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "when signed in as author" do
      before do
        sign_in comment_author
        set_mfa_verified_in_session
      end

      it "returns turbo-stream remove and updates count" do
        comment = create(:feature_request_comment, feature_request: fr_for_comment, user: comment_author, body: approved_comment_body)
        expect(comment.reload.moderation_status).to eq("approved")
        delete roadmap_comment_path(comment), headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq(Mime[:turbo_stream])
        expect(response.body).to include('action="remove"', "roadmap_comment_#{comment.id}")
        expect(response.body).to include('target="roadmap_comments_count"')
        expect(comment.reload.deleted_at).to be_present
      end

      it "appends empty state when the last visible comment is deleted" do
        comment = create(:feature_request_comment, feature_request: fr_for_comment, user: comment_author, body: approved_comment_body)
        expect(comment.reload.moderation_status).to eq("approved")
        delete roadmap_comment_path(comment), headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response.body).to include("roadmap-comments-empty")
        expect(response.body).to include(I18n.t("roadmap.comments.empty_state"))
      end

      it "returns JSON ok when Accept is JSON" do
        comment = create(:feature_request_comment, feature_request: fr_for_comment, user: comment_author, body: approved_comment_body)
        delete roadmap_comment_path(comment), as: :json
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)["ok"]).to be(true)
      end

      it "returns 404 turbo-stream for unknown comment id" do
        delete roadmap_comment_path(9_999_999), headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:not_found)
        expect(response.body).to include("roadmap_comment_form_errors")
        expect(response.body).to include(I18n.t("roadmap.comments.not_found"))
      end
    end

    context "when signed in as another user" do
      let(:other_user) do
        u = create(:user)
        u.update!(auth_method: "discord")
        u
      end

      before do
        sign_in other_user
        set_mfa_verified_in_session
      end

      it "returns 403 turbo-stream when comment belongs to someone else" do
        comment = create(:feature_request_comment, feature_request: fr_for_comment, user: comment_author, body: approved_comment_body)
        expect(comment.reload.moderation_status).to eq("approved")
        delete roadmap_comment_path(comment), headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include("roadmap_comment_form_errors")
        expect(response.body).to include(I18n.t("roadmap.comments.cannot_delete"))
        expect(comment.reload.deleted_at).to be_nil
      end
    end
  end
end
