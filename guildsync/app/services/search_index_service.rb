# frozen_string_literal: true

# Service for indexing and managing documents in Typesense search
class SearchIndexService
  class << self
    def client
      TypesenseConfig.client
    end

    def collection
      client.collections[TypesenseConfig.collection_name]
    end

    def enabled?
      TypesenseConfig.enabled?
    end

    # Index a single document
    def index(record)
      return unless enabled?
      return unless record.present?

      document = build_document(record)
      return unless document

      begin
        collection.documents.upsert(document)
        Rails.logger.debug "Indexed #{record.class.name}##{record.id} in Typesense"
      rescue => e
        Rails.logger.error "Failed to index #{record.class.name}##{record.id}: #{e.message}"
      end
    end

    # Remove a document from the index
    def remove(record)
      return unless enabled?
      return unless record.present?

      document_id = build_document_id(record)
      return unless document_id

      begin
        collection.documents[document_id].delete
        Rails.logger.debug "Removed #{record.class.name}##{record.id} from Typesense"
      rescue Typesense::Error::ObjectNotFound
        # Document doesn't exist, that's fine
      rescue => e
        Rails.logger.error "Failed to remove #{record.class.name}##{record.id}: #{e.message}"
      end
    end

    # Reindex all records of a given model
    def reindex_all(model_class)
      return unless enabled?

      Rails.logger.info "Reindexing all #{model_class.name} records..."
      
      model_class.find_each do |record|
        index(record)
      end
      
      Rails.logger.info "Finished reindexing #{model_class.name}"
    end

    # Reindex everything
    def reindex_everything!
      return unless enabled?

      Rails.logger.info "Reindexing all searchable content..."
      
      TypesenseConfig.recreate_collection!
      
      # Index all searchable models
      reindex_all(Event)
      reindex_all(Poll)
      reindex_all(DiscordEvent)
      reindex_all(GuildDocument)
      reindex_all(LootRoll)
      
      Rails.logger.info "Finished reindexing all content"
    end

    private

    def build_document_id(record)
      "#{record.class.name.underscore}_#{record.id}"
    end

    def build_document(record)
      case record
      when Event
        build_event_document(record)
      when Poll
        build_poll_document(record)
      when DiscordEvent
        build_discord_event_document(record)
      when GuildDocument
        build_guild_document_document(record)
      when LootRoll
        build_loot_roll_document(record)
      else
        Rails.logger.warn "Unknown record type for indexing: #{record.class.name}"
        nil
      end
    end

    def build_event_document(event)
      {
        "id" => build_document_id(event),
        "type" => "event",
        "guild_id" => event.guild_id.to_s,
        "guild_name" => event.guild&.name,
        "visibility" => "guild", # Events are guild-only
        "owner_user_id" => event.guild&.owner_id.to_s,
        "allowed_role_ids" => [],
        "allowed_user_ids" => [],
        "title" => event.title,
        "description" => event.description.to_s,
        "created_at" => event.created_at.to_i,
        "url" => "/guilds/#{event.guild_id}"
      }
    end

    def build_poll_document(poll)
      {
        "id" => build_document_id(poll),
        "type" => "poll",
        "guild_id" => poll.guild_id.to_s,
        "guild_name" => poll.guild&.name,
        "visibility" => "guild", # Polls are guild-only
        "owner_user_id" => poll.guild&.owner_id.to_s,
        "allowed_role_ids" => poll.discord_role_mentions || [],
        "allowed_user_ids" => [],
        "title" => poll.title,
        "description" => poll.description.to_s,
        "created_at" => poll.created_at.to_i,
        "url" => "/guilds/#{poll.guild_id}/polls/#{poll.id}"
      }
    end

    def build_discord_event_document(discord_event)
      {
        "id" => build_document_id(discord_event),
        "type" => "scheduled_event",
        "guild_id" => discord_event.guild_id.to_s,
        "guild_name" => discord_event.guild&.name,
        "visibility" => "guild", # Discord events are guild-only
        "owner_user_id" => discord_event.guild&.owner_id.to_s,
        "allowed_role_ids" => [],
        "allowed_user_ids" => [],
        "title" => discord_event.title,
        "description" => discord_event.description.to_s,
        "created_at" => discord_event.created_at.to_i,
        "url" => "/guilds/#{discord_event.guild_id}/discord_events/#{discord_event.id}"
      }
    end

    def build_guild_document_document(doc)
      visibility = case doc.visibility
                   when "public_doc" then "public"
                   when "unlisted_doc" then "public" # Unlisted is still accessible by link
                   else "guild"
                   end

      {
        "id" => build_document_id(doc),
        "type" => "document",
        "guild_id" => doc.guild_id.to_s,
        "guild_name" => doc.guild&.name,
        "visibility" => visibility,
        "owner_user_id" => doc.user_id.to_s,
        "allowed_role_ids" => [],
        "allowed_user_ids" => [doc.user_id.to_s], # Creator always has access
        "title" => doc.title,
        "description" => "", # Documents don't have description, content is too long
        "created_at" => doc.created_at.to_i,
        "url" => "/guilds/#{doc.guild_id}/documents/#{doc.id}"
      }
    end

    def build_loot_roll_document(loot_roll)
      {
        "id" => build_document_id(loot_roll),
        "type" => "loot_roll",
        "guild_id" => loot_roll.guild_id.to_s,
        "guild_name" => loot_roll.guild&.name,
        "visibility" => "guild", # Loot rolls are guild-only
        "owner_user_id" => loot_roll.guild&.owner_id.to_s,
        "allowed_role_ids" => loot_roll.allowed_role_ids || [],
        "allowed_user_ids" => [loot_roll.creator_id.to_s],
        "title" => loot_roll.title,
        "description" => loot_roll.description.to_s,
        "created_at" => loot_roll.created_at.to_i,
        "url" => "/guilds/#{loot_roll.guild_id}/loot_rolls/#{loot_roll.id}"
      }
    end
  end
end
