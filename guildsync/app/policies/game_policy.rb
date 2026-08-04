class GamePolicy < ApplicationPolicy
  def index?
    admin_user?
  end
  
  def show?
    admin_user?
  end
  
  def new?
    admin_user?
  end
  
  def create?
    admin_user?
  end
  
  def edit?
    admin_user?
  end
  
  def update?
    admin_user?
  end
  
  def destroy?
    admin_user?
  end
  
  def toggle_active?
    admin_user?
  end
  
  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin_user?
        scope.all
      else
        scope.none
      end
    end
  end
  
  private
  
  def admin_user?
    return false unless user
    
    # Check environment variable for admin emails
    admin_emails = ENV.fetch('ADMIN_EMAILS', '').split(',').map(&:strip).reject(&:blank?)
    return true if admin_emails.include?(user.email)
    
    # Check environment variable for admin user IDs
    admin_user_ids = ENV.fetch('ADMIN_USER_IDS', '').split(',').map(&:strip).reject(&:blank?).map(&:to_i)
    return true if admin_user_ids.include?(user.id)
    
    # Future: Check for admin attribute on User model
    # return true if user.respond_to?(:admin?) && user.admin?
    
    false
  end
end

