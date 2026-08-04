# frozen_string_literal: true

module UserRestoration
  # Models and scopes for point-in-time restore. Order: parents before children (FK-safe).
  class Registry
    class << self
      def owned_guild_ids(user)
        Guild.where(owner_id: user.id).pluck(:id)
      end

      # Alliances tied to this user's owned guilds OR where the user is the alliance leader.
      def alliance_ids_for_user(user)
        gid = owned_guild_ids(user)
        from_guilds = gid.any? ? Alliance.where(leader_guild_id: gid).pluck(:id) : []
        from_leader = Alliance.where(leader_user_id: user.id).pluck(:id)
        (from_guilds + from_leader).uniq
      end

      def restore_order
        @restore_order ||= [
          User,
          Guild,
          GuildDiscordSetting,
          DiscordConnection,
          GuildGame,
          Event,
          EventParticipation,
          DiscordEvent,
          DiscordEventParticipation,
          DiscordEventSignup,
          GuildMember,
          GuildMemberTag,
          GuildTag,
          GuildDocument,
          GuildDocumentFolder,
          GuildDocumentImage,
          Poll,
          PollVote,
          LootRoll,
          LootRollEntry,
          GuildInvite,
          GuildApplication,
          GearSnapshot,
          GearUploadRequest,
          GuildActivityLog,
          FileEntry,
          Folder,
          ReactRole,
          GuildInviteLink,
          DirectMessage,
          GuildMemberWarningStatus,
          DiscordRoleSync,
          Alliance,
          AllianceGuild,
          AllianceMember,
          AllianceMemberTag,
          AllianceJoinRequest,
          AllianceEvent,
          AllianceEventParticipation,
          AlliancePoll,
          AlliancePollVote,
          AllianceLootRoll,
          AllianceLootRollEntry,
          AllianceActivityLog,
          AllianceMessage,
          AllianceInvite,
          AllianceTag,
          AllianceDisbandVote,
          AllianceEventDiscordMessage,
          AllianceEventDiscordSignup,
          AllianceLootRollDiscordMessage,
          AlliancePollDiscordMessage,
          UserRecentActivity,
          LoginHistory,
          UserDiscordConnection,
          FeatureRequest,
          FeatureRequestVote,
          FeatureRequestComment,
          BackupCode,
          BackupCodeUsageLog,
          UserComplianceWarning,
          UserWarning,
          OcrRequest,
          OcrDenial,
          OcrUsageChange
        ].freeze
      end

      def delete_order
        @delete_order ||= restore_order.reverse
      end

      def scope_for(klass, user)
        gid = owned_guild_ids(user)
        aids = alliance_ids_for_user(user)

        case klass.name
        when "User"
          klass.where(id: user.id)
        when "Guild"
          klass.where(owner_id: user.id)
        when "GuildMember"
          if gid.any?
            klass.where(guild_id: gid).or(
              klass.where(user_id: user.id).where.not(guild_id: gid)
            )
          else
            klass.where(user_id: user.id)
          end
        when "GuildDiscordSetting", "DiscordConnection", "GuildGame", "GuildDocument",
             "GuildDocumentFolder", "GuildDocumentImage", "Poll", "LootRoll",
             "GuildInvite", "GuildApplication", "GearSnapshot", "GearUploadRequest",
             "GuildActivityLog", "FileEntry", "Folder", "ReactRole", "GuildInviteLink",
             "DirectMessage", "GuildMemberWarningStatus", "DiscordRoleSync"
          return klass.none if gid.empty?

          klass.where(guild_id: gid)
        when "Event"
          return klass.none if gid.empty?

          klass.where(guild_id: gid)
        when "EventParticipation"
          return klass.none if gid.empty?

          klass.joins(:event).where(events: { guild_id: gid })
        when "DiscordEvent"
          return klass.none if gid.empty?

          klass.where(guild_id: gid)
        when "DiscordEventParticipation"
          return klass.none if gid.empty?

          klass.joins(:event).where(events: { guild_id: gid })
        when "DiscordEventSignup"
          return klass.none if gid.empty?

          klass.joins(:discord_event).where(discord_events: { guild_id: gid })
        when "GuildMemberTag"
          if gid.any?
            gm_owned = GuildMember.where(guild_id: gid)
            gm_member_only = GuildMember.where(user_id: user.id).where.not(guild_id: gid)
            klass.joins(:guild_member).merge(gm_owned.or(gm_member_only))
          else
            klass.joins(:guild_member).where(guild_members: { user_id: user.id })
          end
        when "GuildTag"
          return klass.none if gid.empty?

          klass.where(guild_id: gid)
        when "PollVote"
          return klass.none if gid.empty?

          klass.joins(:poll).where(polls: { guild_id: gid })
        when "LootRollEntry"
          return klass.none if gid.empty?

          klass.joins(:loot_roll).where(loot_rolls: { guild_id: gid })
        when "Alliance"
          scopes = []
          scopes << klass.where(leader_guild_id: gid) if gid.any?
          scopes << klass.where(leader_user_id: user.id)
          scopes.reduce { |acc, rel| acc.or(rel) }
        when "AllianceGuild", "AllianceJoinRequest"
          return klass.none if aids.empty?

          klass.where(alliance_id: aids)
        when "AllianceMember"
          if gid.any? && aids.any?
            klass.where(guild_id: gid).or(klass.where(alliance_id: aids, user_id: user.id))
          elsif gid.any?
            klass.where(guild_id: gid)
          elsif aids.any?
            klass.where(alliance_id: aids, user_id: user.id)
          else
            klass.none
          end
        when "AllianceEvent", "AlliancePoll", "AllianceLootRoll", "AllianceActivityLog", "AllianceMessage",
             "AllianceInvite", "AllianceTag", "AllianceDisbandVote"
          return klass.none if aids.empty?

          klass.where(alliance_id: aids)
        when "AllianceEventParticipation"
          return klass.none if aids.empty?

          klass.joins(:alliance_event).where(alliance_events: { alliance_id: aids })
        when "AlliancePollVote"
          return klass.none if aids.empty?

          klass.joins(:alliance_poll).where(alliance_polls: { alliance_id: aids })
        when "AllianceLootRollEntry"
          return klass.none if aids.empty?

          klass.joins(:alliance_loot_roll).where(alliance_loot_rolls: { alliance_id: aids })
        when "AllianceMemberTag"
          return klass.none if aids.empty?

          klass.joins(:alliance_member).where(alliance_members: { alliance_id: aids })
        when "AllianceEventDiscordMessage", "AllianceLootRollDiscordMessage", "AlliancePollDiscordMessage"
          return klass.none if gid.empty?

          klass.where(guild_id: gid)
        when "AllianceEventDiscordSignup"
          return klass.none if aids.empty?

          klass.joins(:alliance_event).where(alliance_events: { alliance_id: aids })
        when "UserRecentActivity", "LoginHistory", "UserDiscordConnection",
             "FeatureRequest", "FeatureRequestVote", "FeatureRequestComment", "BackupCode",
             "BackupCodeUsageLog", "UserComplianceWarning", "UserWarning", "OcrRequest", "OcrDenial",
             "OcrUsageChange"
          klass.where(user_id: user.id)
        else
          klass.none
        end
      end
    end
  end
end
