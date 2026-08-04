# frozen_string_literal: true

class SoftDeletedRecordRegistry
  RECORD_TYPES = {
    "Event" => Event,
    "DiscordEvent" => DiscordEvent,
    "Poll" => Poll,
    "LootRoll" => LootRoll,
    "GuildDocument" => GuildDocument,
    "Folder" => Folder,
    "FileEntry" => FileEntry,
    "AllianceEvent" => AllianceEvent,
    "AlliancePoll" => AlliancePoll,
    "AllianceLootRoll" => AllianceLootRoll,
    "LandingUserFeedback" => LandingUserFeedback,
    "HomepageFeatureCard" => HomepageFeatureCard,
    "FeatureRequest" => FeatureRequest,
    "FeatureRequestComment" => FeatureRequestComment
  }.freeze

  class << self
    def classes
      RECORD_TYPES.values
    end

    def fetch(type_name)
      RECORD_TYPES[type_name.to_s]
    end

    def type_options
      RECORD_TYPES.keys.map { |type_name| [ fetch(type_name).model_name.human.pluralize, type_name ] }
    end
  end
end
