class Guild < ApplicationRecord
  ARCHIVE_RETENTION_PERIOD = 1.year
  MAX_ACTIVE_INVITE_LINKS = 10

  belongs_to :owner, class_name: "User"
  has_many :guild_members, dependent: :destroy
  has_many :members, through: :guild_members, source: :user
  has_many :events, dependent: :destroy
  has_one :guild_discord_setting, dependent: :destroy
  has_one :discord_connection, dependent: :destroy
  has_many :discord_events, dependent: :destroy
  has_many :guild_applications, dependent: :destroy
  has_many :discord_role_syncs, dependent: :destroy
  has_many :guild_invites, dependent: :destroy
  has_many :guild_invite_links, dependent: :destroy
  has_many :guild_games, dependent: :destroy
  has_many :games, through: :guild_games
  has_many :gear_snapshots, dependent: :destroy
  has_many :gear_upload_requests, dependent: :destroy
  has_many :guild_documents, dependent: :destroy
  has_many :guild_document_folders, dependent: :destroy
  has_many :guild_document_images, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :file_entries, dependent: :destroy
  has_many :polls, dependent: :destroy
  has_many :loot_rolls, dependent: :destroy
  has_many :guild_activity_logs, dependent: :destroy
  has_many :direct_messages, dependent: :nullify
  has_many :react_roles, dependent: :destroy
  has_many :guild_member_warning_statuses, dependent: :destroy
  has_many :guild_tags, dependent: :destroy

  # Alliance associations
  has_many :alliance_guild_memberships, class_name: "AllianceGuild", dependent: :destroy
  has_one  :alliance_guild, -> { where(status: :active) }, class_name: "AllianceGuild"
  has_one  :alliance, through: :alliance_guild
  has_many :alliance_members, dependent: :destroy
  has_many :alliance_join_requests, foreign_key: :requesting_guild_id, dependent: :destroy, inverse_of: :requesting_guild

  # Active Storage
  has_one_attached :logo

  include ValidatesImageAttachment
  validates_image_attachment :logo

  validates :name, presence: true, length: { minimum: 3, maximum: 100 }
  validates :name, uniqueness: { scope: :owner_id, message: :already_owned }
  validates :description, length: { maximum: 1000 }, allow_blank: true
  validates :discord_invite_url,
            allow_blank: true,
            length: { maximum: 512 },
            format: { with: %r{\Ahttps?://\S+\z}i, message: :invalid }
  validate :owner_can_create_guild, on: :create
  validate :permission_roles_are_unique
  before_validation :apply_recruiting_visibility_for_name, on: :create

  scope :not_archived, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :purge_ready, -> { archived.where("scheduled_purge_at <= ?", Time.current) }

  # Connected Discord server name (from bot/settings), else in-app guild name — for embeds.
  def discord_server_display_name
    guild_discord_setting&.discord_guild_name.presence || name
  end

  scope :active, -> { joins(:guild_members).where(guild_members: { status: :active }).distinct }
  scope :publicly_listed, -> { where(publicly_listed: true) }
  # Browsing / applying (member dashboard, guild application form): listed and active guild only.
  scope :discoverable_for_applications, -> { publicly_listed.merge(not_archived) }

  after_commit :sync_alliance_members_if_permission_config_changed, on: :update

  # Helper methods for games
  def primary_game
    games.joins(:guild_games).where(guild_games: { primary: true }).first
  end

  def has_game?(game)
    games.include?(game)
  end

  def archived?
    archived_at.present?
  end

  def archive!(actor:)
    raise ArgumentError, "Only the guild owner can archive this guild" unless actor == owner
    return if archived?

    now = Time.current
    update!(
      archived_at: now,
      scheduled_purge_at: now + ARCHIVE_RETENTION_PERIOD
    )
  end

  def unarchive!(actor:)
    raise ArgumentError, "Only the guild owner can unarchive this guild" unless actor == owner
    return unless archived?

    can_activate = owner.can_activate_additional_owned_guild?(excluding_guild: self)
    raise ArgumentError, "Guild cannot be unarchived under current plan limits" unless can_activate

    update!(archived_at: nil, scheduled_purge_at: nil)
  end

  def eligible_for_purge?
    archived? && scheduled_purge_at.present? && scheduled_purge_at <= Time.current
  end

  def usable_invite_links_count
    guild_invite_links.where("expires_at IS NULL OR expires_at > ?", Time.current).count
  end

  def invite_links_at_capacity?
    usable_invite_links_count >= MAX_ACTIVE_INVITE_LINKS
  end

  # True if +user+ has +permission_suffix+ (e.g. :can_manage_discord_channels) as owner
  # or via a matching permission_role_* slot. Same rules as ApplicationController#role_permission_enabled_for?.
  def role_permission_enabled_for?(user, permission_suffix)
    return false unless user
    return true if owner_id == user.id
    return false unless permission_role_1_id.present? || permission_role_2_id.present? ||
      permission_role_3_id.present? || permission_role_4_id.present?

    target_member = guild_members.find_by(user: user, status: :active)
    target_role_id = target_member&.discord_role_id
    return false if target_role_id.blank?

    (1..4).any? do |slot|
      send(:"permission_role_#{slot}_id") == target_role_id &&
        send(:"role_#{slot}_#{permission_suffix}?")
    end
  end

  def purge!
    raise ArgumentError, "Guild is not eligible for purge" unless eligible_for_purge?

    destroy!
  end

  private

  def apply_recruiting_visibility_for_name
    return if name.blank?
    return if RecruitingVisibilityService.publicly_recruitable?(name)

    self.publicly_listed = false
  end

  def sync_alliance_members_if_permission_config_changed
    return unless alliance_guild&.active?
    return unless alliance_permission_fields_changed?

    AllianceMemberSyncService.new(alliance_guild.alliance, self).sync!
  end

  def alliance_permission_fields_changed?
    saved_change_to_permission_role_1_id? ||
      saved_change_to_permission_role_2_id? ||
      saved_change_to_permission_role_3_id? ||
      saved_change_to_permission_role_4_id? ||
      saved_change_to_role_1_can_manage_alliance? ||
      saved_change_to_role_2_can_manage_alliance? ||
      saved_change_to_role_3_can_manage_alliance? ||
      saved_change_to_role_4_can_manage_alliance? ||
      saved_change_to_role_1_can_invite_alliance_guilds? ||
      saved_change_to_role_2_can_invite_alliance_guilds? ||
      saved_change_to_role_3_can_invite_alliance_guilds? ||
      saved_change_to_role_4_can_invite_alliance_guilds? ||
      saved_change_to_role_1_can_kick_alliance_guilds? ||
      saved_change_to_role_2_can_kick_alliance_guilds? ||
      saved_change_to_role_3_can_kick_alliance_guilds? ||
      saved_change_to_role_4_can_kick_alliance_guilds?
  end

  def owner_can_create_guild
    return unless owner

    plan = owner.current_plan
    unless plan
      errors.add(:base, :subscription_required)
      return
    end

    unless owner.can_create_guild?
      errors.add(:base, :guild_limit_reached, max_guilds: plan.max_guilds, plan_name: plan.name)
    end
  end

  def permission_roles_are_unique
    selected_role_ids = [
      permission_role_1_id,
      permission_role_2_id,
      permission_role_3_id,
      permission_role_4_id
    ].filter_map { |role_id| role_id.presence }

    return unless selected_role_ids.uniq.length != selected_role_ids.length

    errors.add(:base, :duplicate_permission_role)
  end
end
