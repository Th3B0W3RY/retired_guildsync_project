# frozen_string_literal: true

require "rails_helper"
require "erb"

RSpec.describe "Admin::GuildTransfers", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }
  let(:old_owner) { create(:user, email: "old@test.com") }
  let(:new_owner) { create(:user, email: "new@test.com") }
  let(:guild) { create(:guild, owner: old_owner, name: "Test Guild") }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/guild_transfers/new/:guild_id" do
    it "shows transfer form" do
      get new_guild_transfer_admin_guild_transfers_path(guild_id: guild.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.guild_transfers.new.page_title"))
      expect(response.body).to include(I18n.t("admin.guild_transfers.new.guild_with_name", name: guild.name))
      expect(response.body).to include(I18n.t("admin.guild_transfers.new.transfer_submit"))
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      get new_guild_transfer_admin_guild_transfers_path(guild_id: guild.id),
        headers: { "Turbo-Frame" => Admin::GuildTransfersController::GUILD_TRANSFERS_NEW_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_guild_transfers_new_main"))
      expect(response.body).to include(I18n.t("admin.guild_transfers.new.transfer_submit"))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("admin.guild_transfers.new.page_title")))
    end
  end

  describe "POST /admin/guild_transfers/create" do
    it "transfers guild ownership" do
      expect(guild.owner).to eq(old_owner)
      post create_guild_transfer_admin_guild_transfers_path, params: {
        guild_id: guild.id,
        new_owner_id: new_owner.id,
        cancel_previous_owner_billing: "0"
      }
      expect(response).to redirect_to(admin_user_path(new_owner))
      expect(flash[:notice]).to include(I18n.t("admin.guild_transfers.flash.transferred"))
      guild.reload
      expect(guild.owner).to eq(new_owner)
    end

    it "creates audit log entry" do
      expect {
        post create_guild_transfer_admin_guild_transfers_path, params: {
          guild_id: guild.id,
          new_owner_id: new_owner.id,
          cancel_previous_owner_billing: "0"
        }
      }.to change(AdminAuditLog, :count).by(1)

      audit_log = AdminAuditLog.last
      expect(audit_log.action).to eq("transfer_guild_ownership")
      expect(audit_log.record_type).to eq("Guild")
    end

    context "when cancel_previous_owner_billing is checked and the previous owner has no other guilds" do
      let(:old_owner) { create(:user, email: "old-owner-billing@test.com", skip_free_plan_subscription: true) }
      let(:new_owner) { create(:user, email: "new-owner-billing@test.com", skip_free_plan_subscription: true) }
      let(:paid_plan) { create(:pricing_plan, name: "Paid X", max_guilds: 5, price: 10, price_display: "$10", period: "month") }

      before do
        create(:subscription, user: old_owner, pricing_plan: paid_plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)
      end

      it "invokes SubscriptionCancellationService for the previous owner" do
        expect(SubscriptionCancellationService).to receive(:call).with(user: old_owner).and_call_original

        post create_guild_transfer_admin_guild_transfers_path, params: {
          guild_id: guild.id,
          new_owner_id: new_owner.id,
          cancel_previous_owner_billing: [ "0", "1" ]
        }

        expect(response).to redirect_to(admin_user_path(new_owner))
        expect(flash[:notice]).to include(I18n.t("admin.guild_transfers.flash.transferred"))
        expect(flash[:notice]).to include(I18n.t("admin.guild_transfers.billing_modes.local"))
      end
    end

    context "when cancel_previous_owner_billing is checked but the previous owner keeps another guild" do
      let(:old_owner) { create(:user, email: "old-two-guilds@test.com", skip_free_plan_subscription: true) }
      let(:new_owner) { create(:user, email: "new-two-guilds@test.com", skip_free_plan_subscription: true) }
      let(:paid_plan) { create(:pricing_plan, name: "Paid Y", max_guilds: 5, price: 10, price_display: "$10", period: "month") }

      before do
        create(:subscription, user: old_owner, pricing_plan: paid_plan, status: :active, started_at: Time.current, stripe_subscription_id: nil)
        create(:guild, owner: old_owner, name: "Keeps This")
      end

      it "does not call SubscriptionCancellationService" do
        expect(SubscriptionCancellationService).not_to receive(:call)

        post create_guild_transfer_admin_guild_transfers_path, params: {
          guild_id: guild.id,
          new_owner_id: new_owner.id,
          cancel_previous_owner_billing: [ "0", "1" ]
        }

        expect(response).to redirect_to(admin_user_path(new_owner))
        expect(flash[:notice]).to include(I18n.t("admin.guild_transfers.flash.billing_skipped_still_owns_guilds"))
      end
    end

    it "returns see_other redirect to new owner when Accept is turbo_stream" do
      post create_guild_transfer_admin_guild_transfers_path,
        params: {
          guild_id: guild.id,
          new_owner_id: new_owner.id,
          cancel_previous_owner_billing: "0"
        },
        headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(admin_user_path(new_owner))
      expect(flash[:notice]).to include(I18n.t("admin.guild_transfers.flash.transferred"))
      expect(guild.reload.owner).to eq(new_owner)
    end
  end

  describe "authentication" do
    before do
      delete "/admin/logout"
    end

    it "requires admin for new" do
      get new_guild_transfer_admin_guild_transfers_path(guild_id: guild.id)
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin for create" do
      expect(guild.owner).to eq(old_owner)
      expect {
        post create_guild_transfer_admin_guild_transfers_path, params: {
          guild_id: guild.id,
          new_owner_id: new_owner.id
        }
      }.not_to change(AdminAuditLog, :count)

      expect(response).to redirect_to(admin_login_path)
      guild.reload
      expect(guild.owner).to eq(old_owner)
    end
  end
end

