# frozen_string_literal: true

class IpMembershipEnforcementService
  WARNING_TYPE = UserComplianceWarning::WARNING_TYPE_IP_CONFLICT
  ESCALATION_THRESHOLD = 3
  LOOKBACK_DAYS = 60
  MAX_LOGIN_IPS = 50

  Result = Struct.new(
    :allowed,
    :message,
    :message_key,
    :conflict_accounts,
    :conflict_guild_ids,
    keyword_init: true
  )

  class ConflictError < StandardError; end

  def feature_enabled?
    ENV["DISABLE_IP_MEMBERSHIP_ENFORCEMENT"] != "true"
  end

  def check_before_guild_join!(user:, target_guild:)
    result = evaluate(user: user, target_guild: target_guild)
    persist_warning_state!(result, user: user)
    raise ConflictError, result.message unless result.allowed
    result
  end

  def audit_user!(user)
    result = evaluate(user: user)
    persist_warning_state!(result, user: user)
    result
  end

  def audit_all_recent!
    return unless feature_enabled?

    candidate_user_ids = User.where.not(signup_ip: [ nil, "" ]).pluck(:id)
    login_user_ids = LoginHistory.where("login_at > ?", LOOKBACK_DAYS.days.ago).where.not(ip_address: [ nil, "" ]).distinct.pluck(:user_id)
    (candidate_user_ids | login_user_ids).each do |user_id|
      user = User.find_by(id: user_id)
      audit_user!(user) if user
    end
  end

  private

  def evaluate(user:, target_guild: nil)
    return allowed_result if user.blank? || !feature_enabled?

    related_users = users_sharing_ips_with(user)
    return allowed_result if related_users.empty?

    target_guild_id = target_guild&.id
    active_memberships = GuildMember.active.where(user_id: related_users.map(&:id)).pluck(:user_id, :guild_id)
    guild_ids_by_user = active_memberships.group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
    return allowed_result if guild_ids_by_user.blank?

    candidate_user_guild_ids = guild_ids_by_user[user.id] || []
    candidate_guild_ids = candidate_user_guild_ids.dup
    candidate_guild_ids << target_guild_id if target_guild_id.present?
    candidate_guild_ids.uniq!

    conflicting_users = related_users.select do |other_user|
      next false if other_user.id == user.id
      other_guild_ids = guild_ids_by_user[other_user.id] || []
      other_guild_ids.any? && (other_guild_ids - candidate_guild_ids).any?
    end

    if conflicting_users.any?
      conflict_guild_ids = conflicting_users.flat_map { |u| guild_ids_by_user[u.id] || [] }.uniq
      conflict_users = (conflicting_users + [ user ]).uniq
      return Result.new(
        allowed: false,
        message: I18n.t("compliance.ip_conflict.warning_message"),
        message_key: "compliance.ip_conflict.warning_message",
        conflict_accounts: conflict_users,
        conflict_guild_ids: conflict_guild_ids
      )
    end

    allowed_result
  end

  def allowed_result
    Result.new(
      allowed: true,
      message: nil,
      message_key: nil,
      conflict_accounts: [],
      conflict_guild_ids: []
    )
  end

  def users_sharing_ips_with(user)
    ips = candidate_ips_for(user)
    return [ user ] if ips.empty?

    signup_ids = User.where(signup_ip: ips).pluck(:id)
    login_ids = LoginHistory.where(ip_address: ips).distinct.pluck(:user_id)
    User.where(id: (signup_ids | login_ids)).to_a
  end

  LOOPBACK_IPS = %w[127.0.0.1 ::1].freeze

  def candidate_ips_for(user)
    ips = []
    ips << user.signup_ip if user.respond_to?(:signup_ip) && user.signup_ip.present?
    ips.concat(user.login_histories.order(login_at: :desc).limit(MAX_LOGIN_IPS).pluck(:ip_address))
    ips.compact.map(&:strip).reject(&:blank?).uniq.reject { |ip| LOOPBACK_IPS.include?(ip) }
  end

  def persist_warning_state!(result, user:)
    return unless feature_enabled?

    if result.allowed
      resolve_user_group_warnings!(user)
      return
    end

    now = Time.current
    result.conflict_accounts.each do |account|
      warning = UserComplianceWarning.find_or_initialize_by(user_id: account.id, warning_type: WARNING_TYPE)
      warning.active = true
      warning.message = I18n.t("compliance.ip_conflict.warning_message")
      warning.conflict_count = warning.conflict_count.to_i + 1
      warning.last_detected_at = now
      warning.resolved_at = nil
      warning.details_json = {
        "conflict_user_ids" => result.conflict_accounts.map(&:id),
        "conflict_guild_ids" => result.conflict_guild_ids
      }

      if warning.conflict_count >= ESCALATION_THRESHOLD
        warning.message = I18n.t("compliance.ip_conflict.lock_message")
        warning.locked_by_policy = true
        account.update_columns(locked_at: now) if account.respond_to?(:locked_at) && account.locked_at.nil?
      end

      warning.save!
    end
  end

  def resolve_user_group_warnings!(user)
    user_ids = users_sharing_ips_with(user).map(&:id)
    user_ids << user.id
    warnings = UserComplianceWarning.active.for_type(WARNING_TYPE).where(user_id: user_ids.uniq)
    warnings.find_each do |warning|
      warning.update!(active: false, resolved_at: Time.current)
      next unless warning.locked_by_policy

      user = warning.user
      user.update_columns(locked_at: nil) if user.respond_to?(:locked_at) && user.locked_at.present?
    end
  end
end
