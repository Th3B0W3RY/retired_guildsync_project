module SubscriptionRequired
  extend ActiveSupport::Concern

  included do
    before_action :require_subscription_or_trial
  end

  private

  def require_subscription_or_trial
    return if current_user&.access_allowed?

    redirect_to pricing_path, alert: t("controllers.subscription_required.trial_ended")
  end
end
