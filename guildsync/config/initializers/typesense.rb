# frozen_string_literal: true

# Typesense configuration for global search
module TypesenseConfig
  class << self
    def client
      @client ||= Typesense::Client.new(
        nodes: [{
          host: ENV.fetch("TYPESENSE_HOST", "localhost"),
          port: ENV.fetch("TYPESENSE_PORT", "8108").to_i,
          protocol: ENV.fetch("TYPESENSE_PROTOCOL", "http")
        }],
        api_key: ENV.fetch("TYPESENSE_API_KEY", "xyz"),
        connection_timeout_seconds: 5,
        retry_interval_seconds: 0.1,
        num_retries: 3
      )
    end

    def collection_name
      "guild_global_search"
    end

    def enabled?
      ENV["TYPESENSE_ENABLED"] == "true"
    end

    # Schema for the global search collection
    def collection_schema
      {
        "name" => collection_name,
        "fields" => [
          { "name" => "id", "type" => "string" },
          { "name" => "type", "type" => "string", "facet" => true },
          { "name" => "guild_id", "type" => "string", "optional" => true, "facet" => true },
          { "name" => "guild_name", "type" => "string", "optional" => true },
          { "name" => "visibility", "type" => "string", "facet" => true },
          { "name" => "owner_user_id", "type" => "string", "facet" => true },
          { "name" => "allowed_role_ids", "type" => "string[]", "optional" => true },
          { "name" => "allowed_user_ids", "type" => "string[]", "optional" => true },
          { "name" => "title", "type" => "string" },
          { "name" => "description", "type" => "string", "optional" => true },
          { "name" => "created_at", "type" => "int64" },
          { "name" => "url", "type" => "string" }
        ],
        "default_sorting_field" => "created_at"
      }
    end

    # Create collection if it doesn't exist
    def ensure_collection_exists!
      return unless enabled?

      begin
        client.collections[collection_name].retrieve
        Rails.logger.info "Typesense collection '#{collection_name}' already exists"
      rescue Typesense::Error::ObjectNotFound
        client.collections.create(collection_schema)
        Rails.logger.info "Created Typesense collection '#{collection_name}'"
      rescue => e
        Rails.logger.error "Failed to ensure Typesense collection exists: #{e.message}"
      end
    end

    # Drop and recreate collection (useful for reindexing)
    def recreate_collection!
      return unless enabled?

      begin
        client.collections[collection_name].delete
        Rails.logger.info "Deleted Typesense collection '#{collection_name}'"
      rescue Typesense::Error::ObjectNotFound
        # Collection doesn't exist, that's fine
      end

      client.collections.create(collection_schema)
      Rails.logger.info "Created Typesense collection '#{collection_name}'"
    end
  end
end
