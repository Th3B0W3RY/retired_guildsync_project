# frozen_string_literal: true

# Concern for models that should be indexed in Typesense search
module Searchable
  extend ActiveSupport::Concern

  included do
    after_commit :sync_search_index, on: [ :create, :update ]
    after_commit :remove_from_search, on: :destroy
  end

  private

  def sync_search_index
    return unless TypesenseConfig.enabled?

    if respond_to?(:saved_change_to_deleted_at?) && saved_change_to_deleted_at?
      deleted? ? remove_from_search : index_for_search
    else
      index_for_search
    end
  end

  def index_for_search
    return unless TypesenseConfig.enabled?
    SearchIndexJob.perform_later(:index, self.class.name, id)
  end

  def remove_from_search
    return unless TypesenseConfig.enabled?
    SearchIndexJob.perform_later(:remove, self.class.name, id)
  end
end
