class GuildPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    return true if record.publicly_listed?

    user.present? && (
      record.owner == user ||
      record.guild_members.exists?(user: user, status: :active)
    )
  end

  def create?
    user.present?
  end

  def update?
    user.present? && (record.owner == user || record.guild_members.find_by(user: user)&.admin? || record.guild_members.find_by(user: user)&.owner?)
  end

  def destroy?
    user.present? && record.owner == user
  end

  def manage_discord?
    update_discord_channels?
  end

  def update_discord_channels?
    user.present? && record.role_permission_enabled_for?(user, :can_manage_discord_channels)
  end

  # API: record Discord signup for an event on behalf of params[:discord_user_id].
  # Any active guild member (or owner) may call this; channel management is separate (#manage_discord?).
  def signup_discord_event_participation?
    return false unless user.present?
    return true if record.owner_id == user.id

    record.guild_members.exists?(user: user, status: :active)
  end
end
