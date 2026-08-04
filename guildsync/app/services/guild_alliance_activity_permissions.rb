# frozen_string_literal: true

# Alliance invite/kick permission checks for activity logging (mirrors ApplicationController).
# Kept separate so AllianceActivityLogger does not depend on a controller instance.
class GuildAllianceActivityPermissions
  class << self
    def non_owner_alliance_privilege?(guild, user)
      return false unless guild && user
      return false if guild.owner_id == user.id

      invite_role?(guild, user) || kick_role?(guild, user)
    end

    def invite_role?(guild, user)
      return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? ||
        guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

      target_member = guild.guild_members.find_by(user: user, status: :active)
      target_role_id = target_member&.discord_role_id
      return false if target_role_id.blank?

      (guild.permission_role_1_id == target_role_id && (guild.role_1_can_invite_alliance_guilds? || guild.role_1_can_manage_alliance?)) ||
        (guild.permission_role_2_id == target_role_id && (guild.role_2_can_invite_alliance_guilds? || guild.role_2_can_manage_alliance?)) ||
        (guild.permission_role_3_id == target_role_id && (guild.role_3_can_invite_alliance_guilds? || guild.role_3_can_manage_alliance?)) ||
        (guild.permission_role_4_id == target_role_id && (guild.role_4_can_invite_alliance_guilds? || guild.role_4_can_manage_alliance?))
    end

    def kick_role?(guild, user)
      return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? ||
        guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

      target_member = guild.guild_members.find_by(user: user, status: :active)
      target_role_id = target_member&.discord_role_id
      return false if target_role_id.blank?

      (guild.permission_role_1_id == target_role_id && (guild.role_1_can_kick_alliance_guilds? || guild.role_1_can_manage_alliance?)) ||
        (guild.permission_role_2_id == target_role_id && (guild.role_2_can_kick_alliance_guilds? || guild.role_2_can_manage_alliance?)) ||
        (guild.permission_role_3_id == target_role_id && (guild.role_3_can_kick_alliance_guilds? || guild.role_3_can_manage_alliance?)) ||
        (guild.permission_role_4_id == target_role_id && (guild.role_4_can_kick_alliance_guilds? || guild.role_4_can_manage_alliance?))
    end
  end
end
