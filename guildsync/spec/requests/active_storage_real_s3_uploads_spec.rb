# frozen_string_literal: true

require "rails_helper"

include ActionDispatch::TestProcess

RSpec.describe "Active Storage real S3 uploads (opt-in)", type: :request, real_network: true do
  REAL_S3_FLAG = "REAL_S3_UPLOADS_IN_SPECS"

  def real_s3_enabled?
    ENV[REAL_S3_FLAG] == "1"
  end

  def required_s3_config_present?
    bucket = ENV["S3_BUCKET"].presence || ENV["AWS_S3_BUCKET_NAME"].presence || ENV["AWS_BUCKET"].presence
    key = ENV["S3_ACCESS_KEY_ID"].presence || ENV["AWS_ACCESS_KEY_ID"].presence
    secret = ENV["S3_SECRET_ACCESS_KEY"].presence || ENV["AWS_SECRET_ACCESS_KEY"].presence
    bucket.present? && key.present? && secret.present?
  end

  before do
    skip "Set #{REAL_S3_FLAG}=1 to run real S3 upload specs" unless real_s3_enabled?
    skip "Missing required S3 env vars" unless required_s3_config_present?
    skip "ACTIVE_STORAGE_SERVICE must be amazon for this spec" unless Rails.application.config.active_storage.service.to_s == "amazon"
  end

  around do |example|
    # Opt-in real network call mode for this spec file only.
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:guild) { create(:guild, owner: user) }
  let(:document_image_upload) { fixture_file_upload(Rails.root.join("spec/fixtures/files/dot.png"), "image/png") }

  before do
    sign_in user
    set_mfa_verified_in_session
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  it "uploads guild document image to real S3 service and stores amazon service_name" do
    post upload_image_guild_documents_path(guild), params: { image: document_image_upload }

    expect(response).to have_http_status(:ok), "Expected 200 but got #{response.status}: #{response.body}"
    record = GuildDocumentImage.last
    expect(record).to be_present
    expect(record.image).to be_attached
    blob = record.image.blob
    expect(blob.service_name.to_s).to eq("amazon")

    service = ActiveStorage::Blob.service
    expect(service.exist?(blob.key)).to be(true)

    # Cleanup: remove the uploaded object from S3 after verification.
    record.image.purge
    expect(service.exist?(blob.key)).to be(false)
  end
end
