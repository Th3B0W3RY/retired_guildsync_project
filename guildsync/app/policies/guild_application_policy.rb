# frozen_string_literal: true

class GuildApplicationPolicy < ApplicationPolicy
  # Guild owner/admin can list all applications for their guild
  def index?
    guild_manager?
  end

  # Owner/admin can see any application; the applicant can see their own
  def show?
    guild_manager? || record.user == user
  end

  # Any authenticated user may submit an application
  def create?
    user.present?
  end

  # Only guild owner/admin can accept or reject
  def update?
    guild_manager?
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
