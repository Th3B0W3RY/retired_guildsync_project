class GearUploadRequest < ApplicationRecord
  belongs_to :guild
  belongs_to :requester, class_name: 'User'
  belongs_to :target_user, class_name: 'User'
  
  enum :status, { pending: 0, completed: 1, cancelled: 2 }
  
  validates :guild_id, :requester_id, :target_user_id, presence: true
  validate :requester_can_request
  
  # Scopes
  scope :pending_for_user, ->(guild, user) {
    where(guild: guild, target_user: user, status: :pending)
  }
  
  # Mark as completed when gear snapshot is uploaded
  def mark_completed!
    update!(status: :completed, completed_at: Time.current)
  end
  
  private
  
  def requester_can_request
    return unless guild && requester
    
    # Check if requester is guild owner
    return if guild.owner_id == requester.id
    
    # Check if requester is a guild member with admin or moderator role
    guild_member = guild.guild_members.find_by(user: requester, status: :active)
    if guild_member && (guild_member.admin? || guild_member.moderator?)
      return
    end

    # Check explicit custom-role gear request permission via synced Discord role.
    if guild_member&.discord_role_id.present?
      role_id = guild_member.discord_role_id
      return if (guild.permission_role_1_id == role_id && guild.role_1_can_manage_gear_requests?) ||
                (guild.permission_role_2_id == role_id && guild.role_2_can_manage_gear_requests?) ||
                (guild.permission_role_3_id == role_id && guild.role_3_can_manage_gear_requests?) ||
                (guild.permission_role_4_id == role_id && guild.role_4_can_manage_gear_requests?)
    end
    
    # If none of the above, they don't have permission
    # Note: Full permission checking (including Discord roles) will be done in the controller
    # This model validation is a basic check to prevent obvious invalid requests
    errors.add(:requester, :no_permission)
  end
end

