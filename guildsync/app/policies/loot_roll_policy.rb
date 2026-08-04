class LootRollPolicy < ApplicationPolicy
  def index?
    # All guild members can view loot rolls
    user && (record.members.include?(user) || record.owner == user)
  end

  def show?
    # All guild members can view loot rolls
    user && (record.guild.members.include?(user) || record.guild.owner == user)
  end

  def new?
    # Only guild owner or users with manage_guild_settings permission can create loot rolls
    # record can be either a LootRoll or a Guild
    return false unless user && record

    guild = record.is_a?(Guild) ? record : record.guild
    return false unless guild

    guild.owner == user || can_manage_guild_settings?(guild)
  end

  def create?
    # record is the loot roll being created
    return false unless user && record && record.guild

    record.guild.owner == user || can_manage_guild_settings?(record.guild)
  end

  def close?
    # Only loot roll creator, guild owner, or users with manage_guild_settings permission can close
    return false unless user && record && record.guild

    record.creator == user || record.guild.owner == user || can_manage_guild_settings?(record.guild)
  end

  def force_reroll?
    # Only loot roll creator, guild owner, or users with manage_guild_settings permission can force reroll
    return false unless user && record && record.guild

    record.creator == user || record.guild.owner == user || can_manage_guild_settings?(record.guild)
  end

  def destroy?
    # Only loot roll creator, guild owner, or users with manage_guild_settings permission can delete
    return false unless user && record && record.guild

    record.creator == user || record.guild.owner == user || can_manage_guild_settings?(record.guild)
  end

  private

  def can_manage_guild_settings?(guild)
    return false unless user && guild

    # Guild owner can always manage settings
    return true if guild.owner == user

    # Check if user has a role with manage_guild_settings permission
    member = guild.guild_members.find_by(user: user, status: :active)
    return false unless member

    role = member.role.to_s
    case role
    when "owner"
      true
    when "role_1"
      guild.role_1_can_manage_guild_settings
    when "role_2"
      guild.role_2_can_manage_guild_settings
    when "role_3"
      guild.role_3_can_manage_guild_settings
    when "role_4"
      guild.role_4_can_manage_guild_settings
    else
      false
    end
  end
end
