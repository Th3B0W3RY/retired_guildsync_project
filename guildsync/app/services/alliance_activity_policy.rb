# frozen_string_literal: true

# Who may generate non-view rows in the Alliance Activity Feed.
class AllianceActivityPolicy
  class << self
    # Alliance leader, guild owner of an active alliance guild, or member with custom invite/kick/manage-alliance role.
    def management_actor?(alliance, user)
      return false unless alliance && user
      return true if alliance.leader_user_id == user.id

      active_ids = alliance.alliance_guilds.where(status: :active).pluck(:guild_id)
      return true if active_ids.any? && user.owned_guilds.where(id: active_ids).exists?

      AllianceMember.where(alliance_id: alliance.id, user_id: user.id, status: :active).includes(:guild).any? do |am|
        g = am.guild
        next false unless g && active_ids.include?(g.id)

        GuildAllianceActivityPermissions.non_owner_alliance_privilege?(g, user)
      end
    end

    def active_alliance_member?(alliance, user)
      return false unless alliance && user

      alliance.alliance_members.exists?(user_id: user.id, status: :active)
    end
  end
end
