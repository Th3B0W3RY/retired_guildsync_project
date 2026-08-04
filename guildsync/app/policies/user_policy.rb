# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  # Users can view their own profile, or if profiles are public, anyone can view
  # For security, we'll require authentication to view profiles
  def show?
    user.present? && (record == user || user_admin?)
  end

  # Users can only update their own profile
  def update?
    user.present? && record == user
  end

  # API account archive uses the same rule as update (self only).
  def archive?
    update?
  end

  # Users can view their own guilds, or admins can view any user's guilds
  def guilds?
    user.present? && (record == user || user_admin?)
  end

  # Scope for filtering users
  class Scope < ApplicationPolicy::Scope
    def resolve
      # Only return users that the current user can see
      # For now, users can only see themselves (privacy-focused)
      if user.present?
        scope.where(id: user.id)
      else
        scope.none
      end
    end
  end

  private

  # Helper method to check if current user is an admin
  # This can be expanded when admin roles are added to the User model
  def user_admin?
    # Check if user has an admin role (when implemented)
    # For now, return false - no admin users yet
    user.respond_to?(:admin?) && user.admin?
  end
end
