class EventPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    guild_member_or_owner?
  end

  def create?
    guild_member_or_owner?
  end

  def update?
    user.present? && (record.created_by == user || record.guild.guild_members.find_by(user: user)&.admin? || record.guild.guild_members.find_by(user: user)&.owner?)
  end

  def destroy?
    user.present? && (record.created_by == user || record.guild.owner == user)
  end

  def participate?
    show?
  end

  def participants?
    show?
  end

  private

  def guild_member_or_owner?
    return false unless user.present?

    g = record.guild
    return true if g.owner_id == user.id

    g.guild_members.exists?(user: user, status: :active)
  end
end
