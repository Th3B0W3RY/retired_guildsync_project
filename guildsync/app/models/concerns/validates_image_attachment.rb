# frozen_string_literal: true

# Shared Active Storage image checks for :avatar / :logo (same allowed types as GuildDocumentImage).
module ValidatesImageAttachment
  extend ActiveSupport::Concern

  ALLOWED_TYPES = %w[image/jpeg image/jpg image/png image/gif image/webp].freeze
  DEFAULT_MAX_MB = 10

  class_methods do
    def validates_image_attachment(attachment_name, max_megabytes: DEFAULT_MAX_MB)
      validate do
        attachment = public_send(attachment_name)
        next unless attachment.attached?

        ct = attachment.content_type.to_s.downcase.strip
        unless ct.present? && ALLOWED_TYPES.include?(ct)
          errors.add(attachment_name, I18n.t("image_attachments.invalid_type"))
        end

        max_bytes = max_megabytes * 1024 * 1024
        next if attachment.byte_size <= max_bytes

        errors.add(attachment_name, I18n.t("image_attachments.too_large", max_mb: max_megabytes))
      end
    end
  end
end
