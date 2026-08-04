# frozen_string_literal: true

# When a user lands on Free (trial end, cancel, webhook): strip alliances from their owned guilds
# and transfer alliance leadership when the lead guild leaves.
class FreePlanDowngradeSideEffects
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return unless @user

    snapshot = { "alliance_ids" => [], "removed_at" => Time.current.iso8601 }
    owned = @user.owned_guilds.not_archived

    owned.find_each do |guild|
      ag = AllianceGuild.find_by(guild_id: guild.id, status: :active)
      next unless ag

      alliance = ag.alliance
      snapshot["alliance_ids"] << alliance.id unless snapshot["alliance_ids"].include?(alliance.id)

      was_leader = alliance.leader_guild_id == guild.id

      ag.update!(status: :left)

      if was_leader
        successor = alliance.alliance_guilds.where(status: :active).order(:created_at).first
        if successor
          new_owner = successor.guild.owner
          alliance.update!(leader_guild_id: successor.guild_id, leader_user_id: new_owner.id)
        end
      end

      alliance.alliance_members.where(guild_id: guild.id, status: :active).update_all(status: AllianceMember.statuses[:removed])
    end

    if snapshot["alliance_ids"].any?
      @user.update_column(:alliance_downgrade_snapshot, snapshot)
    end
  end
end
