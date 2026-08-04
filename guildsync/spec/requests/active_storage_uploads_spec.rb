# frozen_string_literal: true

require "rails_helper"

include ActionDispatch::TestProcess

# Request specs for uploads that use Active Storage (avatar, guild logo, KB/document images).
# In test env the service is :test (config.active_storage.service); in production with
# S3_* ENV set, the same code path uses the :amazon service (S3). These examples verify
# that uploads create attached blobs and that the blob is stored with the configured service.
RSpec.describe "Active Storage uploads (avatar, guild logo, KB document images)", type: :request do
  around do |example|
    previous_service = ActiveStorage::Blob.service
    begin
      unless example.metadata[:s3_integration]
        # Keep baseline upload tests deterministic even when ACTIVE_STORAGE_SERVICE=amazon
        # is set in the shell for S3-focused runs.
        ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch(:test)
      end
      example.run
    ensure
      ActiveStorage::Blob.service = previous_service
    end
  end

  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:guild) { create(:guild, owner: user) }

  let(:upgraded_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
      create(:pricing_plan,
        name: "Upgraded",
        price: 16,
        price_display: "$16",
        period: "per month",
        max_guilds: nil,
        max_members_per_guild: nil,
        active: true,
        display_order: 97)
  end

  def subscribe_upgraded!(u)
    u.subscribe_to_plan!(upgraded_plan)
  end

  # Minimal PNG (1x1 pixel)
  let(:png_upload) do
    png_data = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
      0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
      0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00,
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack("C*")
    file = Tempfile.new(["upload", ".png"])
    file.binmode
    file.write(png_data)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "photo.png")
  end

  before do
    sign_in user
    set_mfa_verified_in_session
    # Match guild_documents_spec so upload_image passes MFA and permission checks
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  describe "PATCH /profile/avatar (avatar upload)" do
    it "stores avatar with Active Storage and blob is persisted" do
      expect {
        patch update_avatar_path, params: { user: { avatar: png_upload } }
      }.to change { ActiveStorage::Attachment.count }.by(1)

      expect(response).to redirect_to(profile_settings_path)
      expect(flash[:notice]).to eq(I18n.t("settings.profile.avatar.updated_notice"))
      user.reload
      expect(user.avatar.attached?).to be true
      blob = user.avatar.blob
      expect(blob).to be_present
      expect(blob.service_name.to_s).to eq(ActiveStorage::Blob.service.name.to_s)
      expect(blob.content_type).to eq("image/png")
    end
  end

  describe "PATCH /guilds/:id (guild logo upload)" do
    it "stores guild logo with Active Storage and blob is persisted" do
      expect {
        patch update_guild_path(guild), params: {
          guild: { logo: png_upload },
          commit: "Save Logo"
        }
      }.to change { ActiveStorage::Attachment.count }.by(1)

      expect(response).to be_redirect
      guild.reload
      expect(guild.logo.attached?).to be true
      blob = guild.logo.blob
      expect(blob).to be_present
      expect(blob.service_name.to_s).to eq(ActiveStorage::Blob.service.name.to_s)
      expect(blob.content_type).to eq("image/png")
    end
  end

  describe "POST /alliances and PATCH /alliances/:id (alliance logo)" do
    let(:alliance_paid_plan) do
      plan = PricingPlan.find_or_create_by!(name: "RSpec Alliance Logo Upload Plan") do |p|
        p.price = 19
        p.price_display = "$19"
        p.period = "per month"
        p.max_guilds = 10
        p.max_members_per_guild = 100
        p.active = true
        p.display_order = 99
        p.can_create_alliance = true
      end
      plan.update!(can_create_alliance: true) unless plan.can_create_alliance?
      plan
    end

    let(:alliance_owner) do
      u = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: alliance_paid_plan, status: :active, started_at: Time.current)
      u
    end

    let(:alliance_guild) { create(:guild, owner: alliance_owner) }

    let(:persisted_alliance) do
      alliance_guild
      a = create(:alliance, leader_guild: alliance_guild, leader_user: alliance_owner)
      create(:alliance_guild, alliance: a, guild: alliance_guild, status: :active, joined_at: Time.current)
      create(:alliance_member, alliance: a, user: alliance_owner, guild: alliance_guild, role: :gm, status: :active)
      a
    end

    before do
      alliance_guild
      sign_in alliance_owner
    end

    it "stores alliance logo on create with Active Storage (same blob service as avatar/guild logo)" do
      expect {
        post alliances_path, params: {
          alliance: {
            name: "Logo Alliance #{SecureRandom.hex(4)}",
            description: "With emblem",
            logo: png_upload
          }
        }
      }.to change(Alliance, :count).by(1)

      expect(response).to be_redirect
      a = Alliance.order(:id).last
      expect(a.logo.attached?).to be true
      expect(a.logo.blob.service_name.to_s).to eq(ActiveStorage::Blob.service.name.to_s)
      expect(a.logo.blob.content_type).to eq("image/png")
    end

    it "stores alliance logo on update with Active Storage" do
      alliance = persisted_alliance
      expect {
        patch alliance_path(alliance), params: { alliance: { name: alliance.name, logo: png_upload } }
      }.to change { ActiveStorage::Attachment.where(record_type: "Alliance", name: "logo").count }.by(1)

      alliance.reload
      expect(alliance.logo.attached?).to be true
      expect(alliance.logo.blob.service_name.to_s).to eq(ActiveStorage::Blob.service.name.to_s)
    end
  end

  describe "POST /guilds/:guild_id/documents/upload_image (KB/document image upload)" do
    let(:document_image_upload) { fixture_file_upload(Rails.root.join("spec/fixtures/files/dot.png"), "image/png") }

    before do
      subscribe_upgraded!(user)
    end

    it "stores image with Active Storage and returns URL" do
      post upload_image_guild_documents_path(guild), params: { image: document_image_upload }

      expect(response).to have_http_status(:ok),
        "Expected 200 but got #{response.status}: #{response.body}"

      json = response.parsed_body
      expect(json["url"]).to be_present

      record = GuildDocumentImage.last
      expect(record).to be_present
      expect(record.image.attached?).to be true
      blob = record.image.blob
      expect(blob).to be_present
      expect(blob.service_name.to_s).to eq(ActiveStorage::Blob.service.name.to_s)
      expect(blob.content_type).to eq("image/png")
    end
  end

  # Verifies that the effective Active Storage service used at runtime is applied to new blobs.
  # Note: specs can override ActiveStorage::Blob.service per example.
  describe "configured storage service" do
    it "uses the current ActiveStorage service for new blobs" do
      patch update_avatar_path, params: { user: { avatar: png_upload } }
      expect(response).to be_redirect
      user.reload
      expect(user.avatar.attached?).to be true
      expect(user.avatar.blob.service_name.to_s).to eq(ActiveStorage::Blob.service.name.to_s)
    end
  end

  # When S3 is configured (e.g. in CI or local with ENV), optionally verify that switching
  # to the :amazon service stores blobs with that service name. Skips when :amazon is not
  # in storage.yml or when we don't want to hit real S3.
  describe "S3 service integration (when :amazon is configured)" do
    it "stores blob with amazon service when ActiveStorage uses :amazon", :s3_integration do
      s3_bucket = ENV["S3_BUCKET"].presence || ENV["AWS_S3_BUCKET_NAME"].presence || ENV["AWS_BUCKET"].presence
      s3_key = ENV["S3_ACCESS_KEY_ID"].presence || ENV["AWS_ACCESS_KEY_ID"].presence
      s3_secret = ENV["S3_SECRET_ACCESS_KEY"].presence || ENV["AWS_SECRET_ACCESS_KEY"].presence
      skip "S3 env not configured for integration test" if s3_bucket.blank? || s3_key.blank? || s3_secret.blank?

      amazon_service = begin
        ActiveStorage::Blob.services.fetch(:amazon)
      rescue KeyError
        nil
      rescue RuntimeError => e
        # e.g. "Missing service adapter for S3" when aws-sdk-s3 is not in the bundle
        skip "S3 adapter not available: #{e.message}"
      end
      skip "amazon service not in config" if amazon_service.nil?

      previous_service = ActiveStorage::Blob.service
      ActiveStorage::Blob.service = amazon_service
      begin
        # Deterministic mode: stub S3 calls in this spec file.
        allow_any_instance_of(ActiveStorage::Service::S3Service).to receive(:upload).and_return(true)
        allow_any_instance_of(ActiveStorage::Service::S3Service).to receive(:exist?).and_return(true)

        patch update_avatar_path, params: { user: { avatar: png_upload } }
        expect(response).to be_redirect
        user.reload
        expect(user.avatar.attached?).to be true
        expect(user.avatar.blob.service_name.to_s).to eq("amazon")
      ensure
        ActiveStorage::Blob.service = previous_service
      end
    end

    it "stores guild document image blob with amazon service for upload_image endpoint", :s3_integration do
      s3_bucket = ENV["S3_BUCKET"].presence || ENV["AWS_S3_BUCKET_NAME"].presence || ENV["AWS_BUCKET"].presence
      s3_key = ENV["S3_ACCESS_KEY_ID"].presence || ENV["AWS_ACCESS_KEY_ID"].presence
      s3_secret = ENV["S3_SECRET_ACCESS_KEY"].presence || ENV["AWS_SECRET_ACCESS_KEY"].presence
      skip "S3 env not configured for integration test" if s3_bucket.blank? || s3_key.blank? || s3_secret.blank?

      amazon_service = begin
        ActiveStorage::Blob.services.fetch(:amazon)
      rescue KeyError
        nil
      rescue RuntimeError => e
        skip "S3 adapter not available: #{e.message}"
      end
      skip "amazon service not in config" if amazon_service.nil?

      previous_service = ActiveStorage::Blob.service
      ActiveStorage::Blob.service = amazon_service
      begin
        allow_any_instance_of(ActiveStorage::Service::S3Service).to receive(:upload).and_return(true)
        allow_any_instance_of(ActiveStorage::Service::S3Service).to receive(:exist?).and_return(true)
        allow_any_instance_of(ActiveStorage::Service::S3Service).to receive(:download).and_return(File.binread(Rails.root.join("spec/fixtures/files/dot.png")))

        # Avoid variant processing making additional network calls in this stubbed spec.
        allow_any_instance_of(GuildDocumentImage).to receive(:public_url).and_return("/rails/active_storage/blobs/fake")

        subscribe_upgraded!(user)

        upload = fixture_file_upload(Rails.root.join("spec/fixtures/files/dot.png"), "image/png")
        post upload_image_guild_documents_path(guild), params: { image: upload }

        expect(response).to have_http_status(:ok)
        record = GuildDocumentImage.last
        expect(record).to be_present
        expect(record.image.attached?).to be true
        expect(record.image.blob.service_name.to_s).to eq("amazon")
      ensure
        ActiveStorage::Blob.service = previous_service
      end
    end
  end
end
