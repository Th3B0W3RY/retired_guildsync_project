# frozen_string_literal: true

require "rails_helper"
require "base64"
require "stringio"

MIN_PNG_FIXTURE = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

RSpec.describe "Admin soft deleted records", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }
  let(:user) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: user) }
  let!(:poll) { create(:poll, guild: guild, creator: user, title: "Recoverable Poll") }

  before do
    poll.soft_delete!
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  def purge_params(record, record_type)
    {
      record_type: record_type,
      purge_confirmation: record.soft_delete_display_name,
      purge_reason: "Requested permanent removal after admin review"
    }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  it "lists deleted records and supports searching" do
    get admin_soft_deleted_records_path, params: { q: "Recoverable" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Soft-Deleted User Data")
    expect(response.body).to include("Recoverable Poll")
    expect(response.body).to include("Poll")
  end

  it "does not list records soft-deleted before the retention window" do
    poll.update_column(:deleted_at, SoftDeletable::RETENTION_PERIOD.ago - 1.day)

    get admin_soft_deleted_records_path, params: { q: "Recoverable" }

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("Recoverable Poll")
  end

  it "rejects restore when the record is outside the retention window" do
    poll.update_column(:deleted_at, SoftDeletable::RETENTION_PERIOD.ago - 1.day)

    patch restore_admin_soft_deleted_record_path(poll.id), params: { record_type: "Poll" }

    expect(response).to redirect_to(admin_soft_deleted_records_path)
    expect(flash[:alert]).to eq(
      I18n.t(
        "admin.soft_deleted_records.flash.outside_retention",
        months: (SoftDeletable::RETENTION_PERIOD / 1.month).to_i
      )
    )
    expect(Poll.with_deleted.find(poll.id)).to be_deleted
  end

  it "still allows permanent purge outside the retention window" do
    poll.update_column(:deleted_at, SoftDeletable::RETENTION_PERIOD.ago - 1.year)

    expect {
      delete purge_admin_soft_deleted_record_path(poll.id), params: purge_params(poll, "Poll")
    }.to change { Poll.with_deleted.count }.by(-1)
  end

  it "restores a soft-deleted file entry with its ActiveStorage attachment" do
    file_entry = create(:file_entry, :with_file, guild: guild, uploaded_by: user.id, name: "restore_me.bin")
    file_entry.soft_delete!

    trashed = FileEntry.with_deleted.find(file_entry.id)
    expect(trashed.file).to be_attached

    patch restore_admin_soft_deleted_record_path(file_entry.id), params: { record_type: "FileEntry" }

    expect(response).to redirect_to(admin_soft_deleted_records_path)
    restored = FileEntry.find(file_entry.id)
    expect(restored).to be_active
    expect(restored.file).to be_attached
  end

  it "permanently purging a file entry removes ActiveStorage" do
    file_entry = create(:file_entry, :with_file, guild: guild, uploaded_by: user.id, name: "purge_me.bin")
    file_entry.soft_delete!

    expect {
      delete purge_admin_soft_deleted_record_path(file_entry.id), params: purge_params(file_entry, "FileEntry")
    }.to change { ActiveStorage::Attachment.count }.by(-1)
      .and change { FileEntry.with_deleted.count }.by(-1)
  end

  it "blocks purge when confirmation text does not match the record label" do
    delete purge_admin_soft_deleted_record_path(poll.id), params: {
      record_type: "Poll",
      purge_confirmation: "wrong label",
      purge_reason: "Requested permanent removal after admin review"
    }

    expect(response).to redirect_to(admin_soft_deleted_records_path)
    expect(flash[:alert]).to eq(
      I18n.t("admin.soft_deleted_records.flash.purge_confirmation_failed", label: poll.soft_delete_display_name)
    )
    expect(Poll.with_deleted.find(poll.id)).to be_deleted
  end

  it "redirects with alert when record_filter is not a registered type (avoids scanning all models)" do
    get admin_soft_deleted_records_path, params: { record_filter: "NotARealType", q: "Recoverable" }

    expect(response).to redirect_to(admin_soft_deleted_records_path(q: "Recoverable"))
    expect(flash[:alert]).to eq(I18n.t("admin.soft_deleted_records.index.invalid_record_filter"))
  end

  it "returns not found when record_type is unknown" do
    patch restore_admin_soft_deleted_record_path(poll.id), params: { record_type: "NotAClass" }

    expect(response).to have_http_status(:not_found)
  end

  it "returns not found when restoring a non-deleted row" do
    poll.restore!
    patch restore_admin_soft_deleted_record_path(poll.id), params: { record_type: "Poll" }

    expect(response).to have_http_status(:not_found)
  end

  it "requires admin authentication" do
    delete "/admin/logout"
    get admin_soft_deleted_records_path

    expect(response).to redirect_to(admin_login_path)
  end

  it "restores a deleted record" do
    patch restore_admin_soft_deleted_record_path(poll.id), params: { record_type: "Poll" }

    expect(response).to redirect_to(admin_soft_deleted_records_path)
    expect(flash[:notice]).to eq(I18n.t("admin.soft_deleted_records.flash.restored", label: poll.reload.title))
    expect(poll).to be_active
  end

  it "purges a deleted record" do
    expect {
      delete purge_admin_soft_deleted_record_path(poll.id), params: purge_params(poll, "Poll")
    }.to change { Poll.with_deleted.count }.by(-1)
  end

  it "permanently purging a guild document removes embedded GuildDocumentImage attachments" do
    doc = create(:guild_document, guild: guild, user: user)
    img = guild.guild_document_images.build(user: user)
    img.image.attach(
      io: StringIO.new(MIN_PNG_FIXTURE),
      filename: "dot.png",
      content_type: "image/png"
    )
    img.save!
    path = Rails.application.routes.url_helpers.rails_blob_path(img.image, only_path: true)
    doc.update!(content: {
      "type" => "doc",
      "content" => [{ "type" => "image", "attrs" => { "src" => path } }]
    })
    doc.soft_delete!

    expect {
      delete purge_admin_soft_deleted_record_path(doc.id), params: purge_params(doc, "GuildDocument")
    }.to change { GuildDocumentImage.count }.by(-1)
      .and change { ActiveStorage::Attachment.where(record_type: "GuildDocumentImage").count }.by(-1)
  end

  it "purging one guild document does not remove an image still embedded in another document" do
    doc1 = create(:guild_document, guild: guild, user: user)
    doc2 = create(:guild_document, guild: guild, user: user)
    img = guild.guild_document_images.build(user: user)
    img.image.attach(
      io: StringIO.new(MIN_PNG_FIXTURE),
      filename: "dot.png",
      content_type: "image/png"
    )
    img.save!
    path = Rails.application.routes.url_helpers.rails_blob_path(img.image, only_path: true)
    body = { "type" => "doc", "content" => [{ "type" => "image", "attrs" => { "src" => path } }] }
    doc1.update!(content: body)
    doc2.update!(content: body)
    doc1.soft_delete!

    expect {
      delete purge_admin_soft_deleted_record_path(doc1.id), params: purge_params(doc1, "GuildDocument")
    }.not_to(change(GuildDocumentImage, :count))
  end
end

RSpec.describe "Admin soft deleted records (landing CMS)", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }
  let!(:feedback) { create(:landing_user_feedback) }

  before do
    feedback.soft_delete!
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  it "restores soft-deleted landing user feedback" do
    patch restore_admin_soft_deleted_record_path(feedback.id), params: { record_type: "LandingUserFeedback" }

    expect(response).to redirect_to(admin_soft_deleted_records_path)
    expect(feedback.reload).to be_active
  end
end
