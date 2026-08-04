# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account deletion flow", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  before do
    clear_enqueued_jobs
    clear_performed_jobs
    ActionMailer::Base.deliveries.clear
  end

  def sign_in_with_mfa_bypass(userish)
    User.skip_mfa_verification_flags[userish.id] = true
    sign_in userish
  end

  it "returns not found when the feature is disabled" do
    user = create(:user, :with_mfa, email: "featoff@example.com")
    sign_in_with_mfa_bypass(user)
    allow(AccountDeletion).to receive(:feature_enabled?).and_return(false)

    post account_deletion_send_code_path

    expect(response).to have_http_status(:not_found)
  end

  it "allows send_code without a confirmation phrase" do
    user = create(:user, :with_mfa, email: "phraseless@example.com")
    sign_in_with_mfa_bypass(user)

    post account_deletion_send_code_path

    expect(response).to redirect_to(account_settings_path)
    expect(flash[:notice]).to eq(I18n.t("account_deletion.flash.code_sent"))
    expect(user.reload.account_deletion_request).to be_present
  end

  it "blocks send_code when the user owns a guild with other active members" do
    owner = create(:user, :with_mfa, email: "owner-delblock-#{SecureRandom.hex(4)}@example.com")
    guild = create(:guild, owner: owner)
    sign_in_with_mfa_bypass(owner)
    create(
      :guild_member,
      guild: guild,
      user: create(:user, email: "member-#{SecureRandom.hex(6)}@example.com"),
      role: :member,
      status: :active
    )

    post account_deletion_send_code_path

    expect(response).to redirect_to(account_settings_path)
    expect(flash[:alert]).to include(I18n.t("account_deletion.flash.blocked.owned_guild_has_members"))
  end

  it "sends a code on success and completes deletion when the code matches" do
    user = create(:user, :with_mfa, email: "bye@example.com", username: "byeuser")
    sign_in_with_mfa_bypass(user)
    allow(AccountDeletionJob).to receive(:perform_async)

    post account_deletion_send_code_path
    expect(response).to redirect_to(account_settings_path)
    expect(flash[:notice]).to eq(I18n.t("account_deletion.flash.code_sent"))

    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    raw = mail.text_part&.decoded || mail.body.decoded
    code = raw[/[A-F0-9]{8}/]
    expect(code).to be_present

    post account_deletion_confirm_path, params: { code: code }

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq(I18n.t("account_deletion.flash.completed"))

    closed = User.find(user.id)
    expect(closed.archived).to be true
    expect(closed.account_closed_at).to be_present
    expect(AccountDeletionJob).to have_received(:perform_async).with(user.id)
  end

  it "rejects an incorrect code" do
    user = create(:user, :with_mfa, email: "badcode@example.com")
    sign_in_with_mfa_bypass(user)

    post account_deletion_send_code_path

    post account_deletion_confirm_path, params: { code: "DEADBEEF" }

    expect(response).to redirect_to(account_settings_path)
    expect(flash[:alert]).to eq(I18n.t("account_deletion.flash.code_invalid"))
    expect(user.reload.archived).to be false
  end

  it "rejects an expired code" do
    user = create(:user, :with_mfa, email: "expired@example.com")
    sign_in_with_mfa_bypass(user)

    post account_deletion_send_code_path

    user.reload.account_deletion_request.update_columns(expires_at: 1.hour.ago)

    post account_deletion_confirm_path, params: { code: "ABCDEF12" }

    expect(response).to redirect_to(account_settings_path)
    expect(flash[:alert]).to eq(I18n.t("account_deletion.flash.code_expired"))
  end

  describe "Rack::Attack account deletion configuration" do
    it "documents send and confirm path throttles in the initializer for non-test envs" do
      source = Rails.root.join("config/initializers/rack_attack.rb").read
      expect(source).to include('"/account/deletion/send_code"')
      expect(source).to include('"/account/deletion/confirm"')
    end
  end
end
