# frozen_string_literal: true

require "rails_helper"
require "base64"
require "stringio"

# Minimal valid PNG (1×1) — avoids relying on binary fixtures in-repo.
MIN_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

RSpec.describe GuildDocument, type: :model do
  describe "hard destroy / admin purge" do
    let(:user) { create(:user) }
    let(:guild) { create(:guild, owner: user) }

    it "purges GuildDocumentImage rows that are only referenced from this document (Active Storage included)" do
      doc = create(:guild_document, guild: guild, user: user)
      img = GuildDocumentImage.new(guild: guild, user: user)
      img.image.attach(
        io: StringIO.new(MIN_PNG),
        filename: "dot.png",
        content_type: "image/png"
      )
      img.save!
      path = Rails.application.routes.url_helpers.rails_blob_path(img.image, only_path: true)
      doc.update!(content: {
        "type" => "doc",
        "content" => [{ "type" => "image", "attrs" => { "src" => path } }]
      })

      expect { doc.destroy! }.to change(GuildDocumentImage, :count).by(-1)
        .and change { ActiveStorage::Attachment.where(record_type: "GuildDocumentImage").count }.by(-1)
    end

    it "keeps a shared image row while another document still references the same blob URL" do
      doc1 = create(:guild_document, guild: guild, user: user)
      doc2 = create(:guild_document, guild: guild, user: user)
      img = GuildDocumentImage.new(guild: guild, user: user)
      img.image.attach(
        io: StringIO.new(MIN_PNG),
        filename: "dot.png",
        content_type: "image/png"
      )
      img.save!
      path = Rails.application.routes.url_helpers.rails_blob_path(img.image, only_path: true)
      body = { "type" => "doc", "content" => [{ "type" => "image", "attrs" => { "src" => path } }] }
      doc1.update!(content: body)
      doc2.update!(content: body)

      expect { doc1.destroy! }.not_to(change(GuildDocumentImage, :count))
      expect(GuildDocumentImage.exists?(img.id)).to be(true)
    end

    it "does not remove images on soft delete (restore must keep src working)" do
      doc = create(:guild_document, guild: guild, user: user)
      img = GuildDocumentImage.new(guild: guild, user: user)
      img.image.attach(
        io: StringIO.new(MIN_PNG),
        filename: "dot.png",
        content_type: "image/png"
      )
      img.save!
      path = Rails.application.routes.url_helpers.rails_blob_path(img.image, only_path: true)
      doc.update!(content: {
        "type" => "doc",
        "content" => [{ "type" => "image", "attrs" => { "src" => path } }]
      })

      expect { doc.soft_delete! }.not_to(change(GuildDocumentImage, :count))
    end
  end
end

RSpec.describe GuildDocuments::TiptapImageSrcs do
  it "walks nested TipTap JSON" do
    json = {
      "type" => "doc",
      "content" => [
        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Hi" }] },
        { "type" => "image", "attrs" => { "src" => "/rails/active_storage/blobs/x" } }
      ]
    }
    expect(described_class.from_node(json)).to contain_exactly("/rails/active_storage/blobs/x")
  end
end
