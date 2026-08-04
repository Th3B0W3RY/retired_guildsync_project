# frozen_string_literal: true

# Policy for gear-related actions
# The record is a Guild object
class GearPolicy < ApplicationPolicy
  def index?
    # All guild members can view gear
    user.present? && record.members.include?(user)
  end
  
  def show?
    # All guild members can view individual gear snapshots
    index?
  end
  
  def upload?
    # All guild members can upload their own gear
    user.present? && record.members.include?(user)
  end
  
  def request_update?
    # Only guild owners and officers can request gear updates
    return false unless user.present?
    return true if record.owner_id == user.id
    
    # Check custom-role permission via Discord role sync.
    guild_member = record.guild_members.find_by(user: user, status: :active)
    return false unless guild_member
    
    role_id = guild_member.discord_role_id
    return false if role_id.blank?
    
    (record.permission_role_1_id == role_id && record.role_1_can_manage_gear_requests?) ||
    (record.permission_role_2_id == role_id && record.role_2_can_manage_gear_requests?) ||
    (record.permission_role_3_id == role_id && record.role_3_can_manage_gear_requests?) ||
    (record.permission_role_4_id == role_id && record.role_4_can_manage_gear_requests?)
  end
  
  def request_bulk?
    # Same permissions as request_update
    request_update?
  end
  
  class Scope < ApplicationPolicy::Scope
    def resolve
      # Users can only see gear for guilds they're members of
      scope.joins(:guild_members)
          .where(guild_members: { user: user, status: :active })
    end
  end
end

