# frozen_string_literal: true

module AccountDeletion
  class EligibilityChecker
    Result = Struct.new(:allowed?, :reason, keyword_init: true)

    def initialize(user)
      @user = user
    end

    def call
      return Result.new(allowed?: false, reason: :already_closed) if @user.archived? || @user.account_closed_at.present?
      if @user.account_deletion_started_at.present? && @user.account_closure_soft_completed_at.blank?
        return Result.new(allowed?: false, reason: :purge_in_progress)
      end
      return Result.new(allowed?: false, reason: :alliance_leader) if alliance_leader_blocked?
      return Result.new(allowed?: false, reason: :owned_guild_has_members) if owned_guild_blocked?

      Result.new(allowed?: true, reason: nil)
    end

    private

    def alliance_leader_blocked?
      Alliance.active_alliances.exists?(leader_user_id: @user.id)
    end

    def owned_guild_blocked?
      @user.owned_guilds.not_archived.any? do |guild|
        guild.guild_members.where(status: :active).where.not(user_id: @user.id).exists?
      end
    end
  end
end
