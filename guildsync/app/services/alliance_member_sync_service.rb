# frozen_string_literal: true

# Syncs alliance membership for a guild whenever its member roster or permission roles change.
class AllianceMemberSyncService
  def initialize(alliance, guild)
    @alliance = alliance
    @guild    = guild
  end

  # Fully synchronise alliance_members for this guild:
  # - Add missing users
  # - Remove users who are no longer guild members
  # - Update roles (GM / Officer / Member)
  def sync!
    return unless @alliance && @guild

    active_guild_user_ids = @guild.guild_members.active.pluck(:user_id) | [ @guild.owner_id ]

    AllianceMember.transaction do
      # Remove members from this guild who are no longer in it
      @alliance.alliance_members
               .where(guild_id: @guild.id, status: :active)
               .where.not(user_id: active_guild_user_ids)
               .update_all(status: 1) # removed

      # Add or update each active guild user
      active_guild_user_ids.each do |user_id|
        role = compute_role(user_id)

        am = @alliance.alliance_members.find_or_initialize_by(user_id: user_id)
        am.guild_id = @guild.id
        am.role     = role
        am.status   = :active
        am.save!
      end
    end
  end

  private

  # GM if guild owner; Officer if user holds a role slot with alliance invite/kick permission; else Member
  def compute_role(user_id)
    return :gm if @guild.owner_id == user_id

    member = @guild.guild_members.find_by(user_id: user_id, status: :active)
    return :member unless member

    role_slot = member.discord_role_id
    return :member if role_slot.blank?

    (1..4).each do |n|
      perm_role_id = @guild.send(:"permission_role_#{n}_id")
      next if perm_role_id.blank? || perm_role_id != role_slot
      has_alliance_permission = @guild.send(:"role_#{n}_can_invite_alliance_guilds") ||
                               @guild.send(:"role_#{n}_can_kick_alliance_guilds") ||
                               @guild.send(:"role_#{n}_can_manage_alliance")
      return :officer if has_alliance_permission
    end

    :member
  end
end
