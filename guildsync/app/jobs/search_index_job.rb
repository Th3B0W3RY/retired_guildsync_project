# frozen_string_literal: true

# Background job for indexing/removing documents in Typesense
class SearchIndexJob < ApplicationJob
  queue_as :default

  # Index a record
  def perform(action, model_class_name, record_id)
    return unless TypesenseConfig.enabled?

    model_class = resolve_searchable_model_class(model_class_name)
    return unless model_class
    
    case action.to_sym
    when :index
      record = model_class.find_by(id: record_id)
      SearchIndexService.index(record) if record
    when :remove
      # Build a minimal object to get the document ID
      fake_record = model_class.new(id: record_id)
      SearchIndexService.remove(fake_record)
    else
      Rails.logger.warn "Unknown search index action: #{action}"
    end
  rescue NameError
    Rails.logger.error "Invalid model class for search indexing: #{model_class_name}"
  rescue => e
    Rails.logger.error "Search index job failed: #{e.message}"
  end

  private

  def resolve_searchable_model_class(model_class_name)
    klass = model_class_name.to_s.safe_constantize
    return nil unless klass && klass < ApplicationRecord
    return klass if klass.included_modules.include?(Searchable)

    Rails.logger.warn "Rejected non-searchable model class for search indexing: #{model_class_name}"
    nil
  end
end
