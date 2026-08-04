class GuildMember < ApplicationRecord
  belongs_to :user
  belongs_to :guild
  has_many :guild_member_tags, dependent: :destroy
  has_many :guild_tags, through: :guild_member_tags

  enum :role, {
    member: 0,
    moderator: 1,
    admin: 2,
    owner: 3
  }

  enum :status, {
    active: 0,
    inactive: 1,
    banned: 2
  }

  validates :user_id, uniqueness: { scope: :guild_id, message: :already_member }
  validate :guild_member_limit_not_exceeded, on: :create
  validate :ip_membership_enforcement_allows_membership

  before_create :set_joined_at
  after_commit :sync_active_alliance_membership
  after_commit :enqueue_ip_membership_audit

  private

  def set_joined_at
    self.joined_at ||= Time.current
  end

  def guild_member_limit_not_exceeded
    return unless guild&.owner

    plan = guild.owner.current_plan
    return unless plan
    return if plan.unlimited_members_per_guild?

    current_member_count = guild.members.count
    if current_member_count >= plan.max_members_per_guild
      errors.add(:base, :member_limit_reached, max_members: plan.max_members_per_guild, plan_name: plan.name)
    end
  end

  def ip_membership_enforcement_allows_membership
    return unless user && guild
    return unless enforcing_active_membership?

    service = IpMembershipEnforcementService.new
    service.check_before_guild_join!(user: user, target_guild: guild)
  rescue IpMembershipEnforcementService::ConflictError => e
    errors.add(:base, e.message)
  end

  def sync_active_alliance_membership
    guild_record = Guild.find_by(id: guild_id)
    return unless guild_record&.alliance_guild&.active?

    AllianceMemberSyncService.new(guild_record.alliance_guild.alliance, guild_record).sync!
  end

  def enforcing_active_membership?
    return false unless active?
    return true if new_record?
    return false unless will_save_change_to_status?

    before_status, after_status = status_change_to_be_saved
    before_status != after_status && after_status == "active"
  end

  def enqueue_ip_membership_audit
    return unless user_id.present?
    return unless ip_membership_audit_relevant_change?

    IpMembershipAuditJob.perform_async(user_id)
  rescue => e
    Rails.logger.warn("[GuildMember] Failed to enqueue IpMembershipAuditJob for user #{user_id}: #{e.message}")
  end

  def ip_membership_audit_relevant_change?
    return true if destroyed?
    return true if previous_changes.key?("guild_id")
    return true if previous_changes.key?("user_id")

    if previous_changes.key?("status")
      before_status, after_status = previous_changes["status"]
      return true if before_status != after_status
    end

    false
  end
end
