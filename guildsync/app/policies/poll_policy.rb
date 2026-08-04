class PollPolicy < ApplicationPolicy
  def index?
    # All guild members can view polls
    user && (record.members.include?(user) || record.owner == user)
  end

  def show?
    # All guild members can view polls
    user && (record.guild.members.include?(user) || record.guild.owner == user)
  end

  def new?
    # Only guild owner or users with manage_guild_settings permission can create polls
    # record can be either a Poll or a Guild
    return false unless user && record
    
    guild = record.is_a?(Guild) ? record : record.guild
    return false unless guild
    
    guild.owner == user || can_manage_polls?(guild)
  end

  def create?
    # record is the poll being created
    return false unless user && record && record.guild
    
    record.guild.owner == user || can_manage_polls?(record.guild)
  end

  def vote?
    # All guild members can vote
    user && record && (record.guild.members.include?(user) || record.guild.owner == user)
  end

  def post_to_discord?
    user && record && (record.guild.owner == user || can_manage_polls?(record.guild))
  end

  def destroy?
    # Only poll creator, guild owner, or users with poll management permission can delete polls
    return false unless user && record && record.guild
    
    record.creator == user || record.guild.owner == user || can_manage_polls?(record.guild)
  end

  private

  def can_manage_polls?(guild)
    return false unless user && guild

    return true if guild.owner == user

    member = guild.guild_members.find_by(user: user, status: :active)
    return false unless member

    role_id = member.discord_role_id
    return false if role_id.blank?

    (guild.permission_role_1_id == role_id && guild.role_1_can_manage_polls?) ||
      (guild.permission_role_2_id == role_id && guild.role_2_can_manage_polls?) ||
      (guild.permission_role_3_id == role_id && guild.role_3_can_manage_polls?) ||
      (guild.permission_role_4_id == role_id && guild.role_4_can_manage_polls?)
  end
end

