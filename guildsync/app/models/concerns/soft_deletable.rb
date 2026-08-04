# frozen_string_literal: true

module SoftDeletable
  extend ActiveSupport::Concern

  # Admin soft-delete UI lists and restores only records still inside this window.
  # Past this age, PurgeExpiredSoftDeletedRecordsJob permanently destroys rows (see #destroy!).
  RETENTION_PERIOD = 6.months

  included do
    scope :active, -> { where(deleted_at: nil) }
    scope :deleted, -> { with_deleted.where.not(deleted_at: nil) }
    scope :with_deleted, -> { unscope(where: :deleted_at) }

    default_scope { active }

    define_model_callbacks :soft_delete, :restore

    class_attribute :soft_delete_display_attribute, instance_accessor: false, default: nil
    class_attribute :soft_delete_search_attributes, instance_accessor: false, default: [].freeze
  end

  class_methods do
    def soft_delete_metadata(display:, search:)
      self.soft_delete_display_attribute = display.to_s
      self.soft_delete_search_attributes = Array(search).map(&:to_s).freeze
    end

    def deleted_within_retention_period
      deleted.where("#{table_name}.deleted_at >= ?", SoftDeletable::RETENTION_PERIOD.ago)
    end
  end

  def deleted?
    deleted_at.present?
  end

  def active?
    !deleted?
  end

  def soft_delete_restorable?
    deleted? && deleted_at >= SoftDeletable::RETENTION_PERIOD.ago
  end

  def soft_delete!(timestamp: Time.current)
    return if deleted?

    self.deleted_at = timestamp

    transaction do
      run_callbacks(:soft_delete) do
        save!(validate: false)
      end
    end
  end

  def restore!
    return unless deleted?

    self.deleted_at = nil

    transaction do
      run_callbacks(:restore) do
        save!(validate: false)
      end
    end
  end

  def soft_delete_display_name
    configured_value = soft_delete_attribute_value(self.class.soft_delete_display_attribute)
    configured_value.presence || "#{self.class.model_name.human} ##{id}"
  end

  def soft_delete_search_text
    search_values = self.class.soft_delete_search_attributes.filter_map do |attribute|
      soft_delete_attribute_value(attribute)
    end

    [
      self.class.model_name.human,
      soft_delete_display_name,
      soft_delete_container_name,
      soft_delete_owner_name,
      search_values.join(" ")
    ].compact.join(" ")
  end

  def soft_delete_owner_name
    owner_record = soft_delete_owner_record
    return unless owner_record

    owner_record.try(:email).presence ||
      owner_record.try(:username).presence ||
      owner_record.try(:name).presence
  end

  def soft_delete_container_name
    container = soft_delete_container_record
    return unless container

    container.try(:name).presence ||
      container.try(:title).presence ||
      "#{container.class.model_name.human} ##{container.id}"
  end

  def soft_delete_owner_record
    [ :creator, :created_by, :user, :uploader ].each do |association_name|
      next unless respond_to?(association_name)

      owner = public_send(association_name)
      return owner if owner.present?
    end
    nil
  end

  def soft_delete_container_record
    [ :guild, :alliance ].each do |association_name|
      next unless respond_to?(association_name)

      container = public_send(association_name)
      return container if container.present?
    end
    nil
  end

  private

  def soft_delete_attribute_value(attribute)
    return if attribute.blank? || !respond_to?(attribute)

    value = public_send(attribute)
    value = value.to_plain_text if value.respond_to?(:to_plain_text)
    value.to_s.strip.presence
  end
end
