class GuildDocument < ApplicationRecord
  include Searchable
  include SoftDeletable

  belongs_to :guild
  belongs_to :user
  belongs_to :folder, class_name: "GuildDocumentFolder", foreign_key: "folder_id", optional: true

  soft_delete_metadata display: :title, search: [ :title, :slug ]

  # Column is text (encrypted payloads); Ruby value remains a Hash via :json cast.
  attribute :content, :json, default: -> { {} }
  encrypts :content, support_unencrypted_data: true

  enum :visibility, { 
    private_doc: 0,    # only guild members with permission can view
    public_doc: 1,     # open to anyone with the share link
    unlisted_doc: 2   # not indexed, but viewable by link
  }, prefix: true

  validates :title, presence: true, length: { minimum: 1, maximum: 255 }
  validates :visibility, presence: true
  validates :slug, presence: true
  validate :slug_unique_across_deleted_records

  before_destroy :purge_embedded_guild_document_images

  before_validation :generate_slug, on: :create
  before_validation :ensure_slug_uniqueness, on: :create

  # Generate slug from title with UUID suffix for uniqueness
  def generate_slug
    return if slug.present? || title.blank?
    
    base_slug = title.parameterize
    uuid_suffix = SecureRandom.hex(4)
    self.slug = "#{base_slug}-#{uuid_suffix}"
  end

  # Ensure slug is unique by appending counter if needed
  def ensure_slug_uniqueness
    return unless slug.present?
    
    base_slug = slug
    counter = 1
    while self.class.unscoped.where(slug: slug).where.not(id: id).exists?
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  # Check if user can view this document
  def can_view?(user)
    return true if visibility_public_doc?
    return false unless user
    
    if visibility_private_doc?
      # Must be guild member
      guild.members.include?(user)
    elsif visibility_unlisted_doc?
      # Anyone with link can view
      true
    else
      false
    end
  end

  # Check if user can edit this document
  def can_edit?(user)
    return false unless user
    return true if user.id == self.user_id # Creator can always edit
    return true if guild.owner_id == user.id # Guild owner can edit
    
    # Check if user is admin
    member = guild.guild_members.find_by(user: user, status: :active)
    return true if member&.admin? || member&.owner?
    
    false
  end

  def slug_unique_across_deleted_records
    return if slug.blank?
    return unless self.class.unscoped.where(slug: slug).where.not(id: id).exists?

    errors.add(:slug, :taken)
  end

  def purge_embedded_guild_document_images
    GuildDocuments::PurgeEmbeddedImages.call(self)
  end
end
