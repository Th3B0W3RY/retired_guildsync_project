class GuildMemberPolicy < ApplicationPolicy
  def create?
    # Only guild owner or admins can add members
    user.present? && (
      record.guild.owner == user ||
      record.guild.guild_members.find_by(user: user)&.admin? ||
      record.guild.guild_members.find_by(user: user)&.owner?
    )
  end

  def update?
    # Only guild owner or admins can update member roles
    user.present? && (
      record.guild.owner == user ||
      record.guild.guild_members.find_by(user: user)&.admin? ||
      record.guild.guild_members.find_by(user: user)&.owner?
    )
  end

  def destroy?
    # Only guild owner or admins can remove members
    # Members cannot remove themselves (they should leave instead)
    user.present? && (
      record.guild.owner == user ||
      record.guild.guild_members.find_by(user: user)&.admin? ||
      record.guild.guild_members.find_by(user: user)&.owner?
    )
  end
end

