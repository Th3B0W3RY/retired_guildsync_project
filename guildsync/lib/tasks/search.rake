# frozen_string_literal: true

namespace :search do
  desc "Ensure Typesense collection exists"
  task setup: :environment do
    if TypesenseConfig.enabled?
      puts "Setting up Typesense collection..."
      TypesenseConfig.ensure_collection_exists!
      puts "Done!"
    else
      puts "Typesense is not enabled. Set TYPESENSE_ENABLED=true to enable."
    end
  end

  desc "Reindex all searchable content"
  task reindex: :environment do
    if TypesenseConfig.enabled?
      puts "Reindexing all searchable content..."
      SearchIndexService.reindex_everything!
      puts "Done!"
    else
      puts "Typesense is not enabled. Set TYPESENSE_ENABLED=true to enable."
    end
  end

  desc "Reindex a specific model (e.g., rake search:reindex_model[Event])"
  task :reindex_model, [:model] => :environment do |t, args|
    unless args[:model]
      puts "Usage: rake search:reindex_model[ModelName]"
      exit 1
    end

    if TypesenseConfig.enabled?
      model_class = args[:model].constantize
      puts "Reindexing #{model_class.name}..."
      SearchIndexService.reindex_all(model_class)
      puts "Done!"
    else
      puts "Typesense is not enabled. Set TYPESENSE_ENABLED=true to enable."
    end
  end

  desc "Check Typesense connection status"
  task status: :environment do
    if TypesenseConfig.enabled?
      begin
        health = TypesenseConfig.client.health.retrieve
        puts "Typesense is healthy: #{health}"
        
        collection = TypesenseConfig.client.collections[TypesenseConfig.collection_name].retrieve
        puts "Collection '#{collection['name']}' has #{collection['num_documents']} documents"
      rescue => e
        puts "Error connecting to Typesense: #{e.message}"
      end
    else
      puts "Typesense is not enabled. Set TYPESENSE_ENABLED=true to enable."
    end
  end

  desc "Drop and recreate the collection (WARNING: deletes all indexed data)"
  task recreate: :environment do
    if TypesenseConfig.enabled?
      print "This will delete all indexed data. Are you sure? (yes/no): "
      answer = $stdin.gets.chomp
      if answer.downcase == "yes"
        puts "Recreating collection..."
        TypesenseConfig.recreate_collection!
        puts "Done! Run 'rake search:reindex' to reindex all content."
      else
        puts "Cancelled."
      end
    else
      puts "Typesense is not enabled. Set TYPESENSE_ENABLED=true to enable."
    end
  end
end
