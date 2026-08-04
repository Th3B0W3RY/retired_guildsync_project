# frozen_string_literal: true

class GuildInvitePolicy < ApplicationPolicy
  def index?
    guild_manager?
  end

  def create?
    guild_manager?
  end

  def destroy?
    guild_manager?
  end

  # Only the invited user can accept their own pending invite
  def accept?
    user.present? && record.user == user
  end

  # Only the invited user can deny their own pending invite
  def deny?
    user.present? && record.user == user
  end

  private

  def guild_manager?
    return false unless user.present?

    g = record.guild
    return true if g.owner_id == user.id

    member = g.guild_members.find_by(user: user)
    member&.admin? || member&.owner?
  end
end
