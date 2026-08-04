# frozen_string_literal: true

class FontawesomeFreeIconsSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = FontawesomeFreeIcons::Sync.new.call
    Rails.logger.info("FontawesomeFreeIconsSyncJob: upserted #{result[:upserted]} icon style rows from #{result[:icon_definitions]} definitions")
  rescue FontawesomeFreeIcons::Sync::Error => e
    Rails.logger.error("FontawesomeFreeIconsSyncJob failed: #{e.message}")
    raise
  end
end
