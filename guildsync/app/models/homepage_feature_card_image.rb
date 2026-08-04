# frozen_string_literal: true

class HomepageFeatureCardImage < ApplicationRecord
  has_one_attached :image

  validates :image, presence: true
  validate :image_content_type
  validate :image_size

  # Same-origin path keeps rendering stable without host defaults.
  def public_url
    return nil unless image.attached?

    helpers = Rails.application.routes.url_helpers
    if image.image?
      variant = image.variant(resize_to_limit: [1920, 1920], saver: { quality: 85 }).processed
      helpers.rails_representation_url(variant, only_path: true)
    else
      helpers.rails_blob_path(image)
    end
  rescue LoadError, ActiveStorage::FileNotFoundError, ActiveStorage::InvariableError => e
    Rails.logger.warn("HomepageFeatureCardImage#public_url: variant failed (#{e.class}), using blob path: #{e.message}")
    safe_blob_path
  rescue StandardError => e
    Rails.logger.warn("HomepageFeatureCardImage#public_url: #{e.class} - #{e.message}, using blob path")
    safe_blob_path
  end

  private

  def safe_blob_path
    Rails.application.routes.url_helpers.rails_blob_path(image)
  rescue StandardError => e
    Rails.logger.warn("HomepageFeatureCardImage#safe_blob_path: #{e.message}")
    nil
  end

  def image_content_type
    return unless image.attached?

    allowed = %w[image/jpeg image/jpg image/png image/gif image/webp]
    return if image.content_type.present? && allowed.include?(image.content_type.to_s.downcase.strip)

    errors.add(:image, "must be JPEG, PNG, GIF, or WebP")
  end

  def image_size
    return unless image.attached?

    max_mb = 10
    return if image.byte_size <= max_mb * 1024 * 1024

    errors.add(:image, "must be under #{max_mb}MB")
  end
end
