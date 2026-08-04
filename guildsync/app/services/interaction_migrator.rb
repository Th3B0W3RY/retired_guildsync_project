# frozen_string_literal: true

class InteractionMigrator
  attr_reader :user, :discord_user_id

  def initialize(user:, discord_user_id:)
    @user = user
    @discord_user_id = discord_user_id.to_s
  end

  def migrate_all!
    ActiveRecord::Base.transaction do
      migrate_poll_votes!
      migrate_event_participations!
      migrate_alliance_poll_votes!
      migrate_alliance_event_participations!
      migrate_alliance_loot_roll_entries!
    end
  end

  private

  def migrate_poll_votes!
    migrate_records!(PollVote.where(discord_user_id: @discord_user_id, user_id: nil), :poll_id)
  end

  def migrate_event_participations!
    migrate_records!(EventParticipation.where(discord_user_id: @discord_user_id, user_id: nil), :event_id)
  end

  def migrate_alliance_poll_votes!
    migrate_records!(AlliancePollVote.where(discord_user_id: @discord_user_id, user_id: nil), :alliance_poll_id)
  end

  def migrate_alliance_event_participations!
    migrate_records!(AllianceEventParticipation.where(discord_user_id: @discord_user_id, user_id: nil), :alliance_event_id)
  end

  def migrate_alliance_loot_roll_entries!
    migrate_records!(AllianceLootRollEntry.where(discord_user_id: @discord_user_id, user_id: nil), :alliance_loot_roll_id)
  end

  def migrate_records!(scope, parent_key)
    scope.find_each do |record|
      existing = record.class.find_by(user_id: @user.id, parent_key => record.send(parent_key))
      if existing
        record.destroy!
      else
        record.update!(user_id: @user.id, discord_user_id: nil, discord_username: nil)
      end
    end
  end
end
