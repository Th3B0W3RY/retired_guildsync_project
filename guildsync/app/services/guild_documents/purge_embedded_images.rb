# frozen_string_literal: true

module GuildDocuments
  # When a guild document is permanently destroyed (e.g. admin purge), remove dedicated
  # GuildDocumentImage rows + Active Storage blobs that are only referenced from this document.
  # Soft delete / restore intentionally leaves blobs in place so image URLs in content keep working.
  class PurgeEmbeddedImages
    def self.call(guild_document)
      new(guild_document).call
    end

    def initialize(guild_document)
      @doc = guild_document
    end

    def call
      return if @doc.guild_id.blank?

      blob_ids = blob_ids_from_document_content
      return if blob_ids.empty?

      find_images_for_blobs(blob_ids).each do |image|
        next if referenced_by_other_guild_documents?(image)

        image.destroy!
      end
    end

    private

    def blob_ids_from_document_content
      TiptapImageSrcs.from_node(@doc.content).filter_map { |src| blob_id_from_embedded_src(src) }.uniq
    end

    def find_images_for_blobs(blob_ids)
      GuildDocumentImage
        .where(guild_id: @doc.guild_id)
        .joins(image_attachment: :blob)
        .where(active_storage_blobs: { id: blob_ids })
    end

    def referenced_by_other_guild_documents?(image)
      return false unless image.image.attached?

      blob_id = image.image.blob_id
      GuildDocument.unscoped.where(guild_id: @doc.guild_id).where.not(id: @doc.id).any? do |other|
        other_blob_ids(other).include?(blob_id)
      end
    end

    def other_blob_ids(other)
      TiptapImageSrcs.from_node(other.content).filter_map { |src| blob_id_from_embedded_src(src) }.uniq
    end

    def blob_id_from_embedded_src(src)
      path = path_only(src)
      return nil if path.blank? || !path.include?("/rails/active_storage/")

      if (m = path.match(%r{/rails/active_storage/blobs/(?:redirect|proxy)/([^/]+)}))
        return ActiveStorage::Blob.find_signed(m[1])&.id
      end

      if (m = path.match(%r{/rails/active_storage/representations/(?:redirect|proxy)/([^/]+)}))
        return ActiveStorage::Blob.find_signed(m[1], purpose: :blob_id)&.id
      end

      nil
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def path_only(src)
      s = src.to_s.strip
      return nil if s.blank?

      if s.start_with?("http://", "https://")
        URI.parse(s).path.split("?", 2).first.presence
      else
        s.split("?", 2).first.presence
      end
    rescue URI::InvalidURIError
      src.to_s.split("?", 2).first.presence
    end
  end
end
