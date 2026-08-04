# frozen_string_literal: true

# Alliance routes require a non-free plan with active access (subscribed? or in-date trial).
# Free plan is always blocked here; expired trials/subscriptions fail access_allowed?.
# Active alliance members on Free may still use read + participation
# (RSVP, vote, roll, chat) in non-strict controllers; management stays behind
# existing permission checks.
#
# Override {#require_paid_plan_for_all_alliance_actions?} returning true to keep
# the legacy "always require paid" behavior (invites, join requests, etc.).
# Override {#alliance_features_plan_blocked_redirect_path} for guild-scoped redirects.
module RequiresPaidPlanForAllianceFeatures
  extend ActiveSupport::Concern

  private

  def require_paid_plan_for_alliance_features
    return unless current_user.blocked_from_alliance_features?
    return if alliance_read_access_allowed_for_blocked_user?

    redirect_to alliance_features_plan_blocked_redirect_path,
                alert: alliance_plan_blocked_alert_message and return
  end

  # Users blocked by plan may pass the gate if they are already synced as an active
  # alliance member on Free (unless this controller is "strict" — see below).
  def alliance_read_access_allowed_for_blocked_user?
    return false if require_paid_plan_for_all_alliance_actions?

    active_alliance_membership_exists?
  end

  # When true, users blocked by plan/access are never exempt (invites, join requests, etc.).
  def require_paid_plan_for_all_alliance_actions?
    false
  end

  def active_alliance_membership_exists?
    current_user.alliance_members.where(status: :active).exists?
  end

  def alliance_plan_blocked_alert_message
    if require_paid_plan_for_all_alliance_actions?
      t("alliances.errors.join_requires_paid_plan")
    else
      t("alliances.errors.plan_required_for_alliance_hub")
    end
  end

  def alliance_features_plan_blocked_redirect_path
    dashboard_path
  end
end
