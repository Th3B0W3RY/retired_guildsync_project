# frozen_string_literal: true

# Fetches profanity lists from configured internet sources and local backup every 6 hours.
# Updates BlockedWord table; logs to ProfanityUpdateLog. No SMTP.
class ProfanityListUpdateJob
  include Sidekiq::Worker

  sidekiq_options retry: 2, queue: :default

  def perform
    Rails.logger.info "Profanity list update starting (6-hour job)"
    sources = defined?(PROFANITY_SOURCES) ? PROFANITY_SOURCES : []
    results = {
      timestamp: Time.current,
      sources_checked: [],
      new_words_added: 0,
      words_removed: 0,
      total_words: 0,
      errors: []
    }
    all_words = Set.new

    sources.each do |source|
      next unless source[:enabled]

      begin
        words = fetch_from_source(source)
        if words.present?
          all_words.merge(words)
          results[:sources_checked] << { "name" => source[:name], "status" => "success", "count" => words.size }
        else
          results[:sources_checked] << { "name" => source[:name], "status" => "empty" }
        end
      rescue => e
        error_msg = "Failed to fetch from #{source[:name]}: #{e.message}"
        Rails.logger.error(error_msg)
        results[:errors] << error_msg
        results[:sources_checked] << { "name" => source[:name], "status" => "failed", "error" => e.message }
      end
    end

    existing = BlockedWord.pluck(:word).to_set
    words_to_add = all_words - existing
    words_to_remove = existing - all_words

    words_to_add.each do |word|
      word_str = word.to_s.strip.downcase
      next if word_str.blank?
      BlockedWord.find_or_initialize_by(word: word_str).tap do |bw|
        bw.assign_attributes(
          category: "profanity",
          source: "dynamic",
          last_seen_at: Time.current,
          active: true,
          deactivated_at: nil
        )
        bw.save!
      end
    end

    if should_remove_old_words?(sources) && words_to_remove.any?
      words_to_remove.each do |word|
        BlockedWord.where(word: word).update_all(active: false, deactivated_at: Time.current)
      end
    end

    results[:new_words_added] = words_to_add.size
    results[:words_removed] = words_to_remove.size
    results[:total_words] = all_words.size

    BlockedContentFilter.reset!
    Rails.cache.delete(BlockedContentFilter::CACHE_KEY)

    ProfanityUpdateLog.create!(
      timestamp: results[:timestamp],
      sources_checked: results[:sources_checked],
      new_words_added: results[:new_words_added],
      words_removed: results[:words_removed],
      total_words: results[:total_words],
      error_messages: results[:errors]
    )

    if words_to_remove.size > 100 && all_words.size < 500
      Rails.logger.warn "Profanity list shrunk dramatically: #{words_to_remove.size} removed, total #{all_words.size}. Check sources."
    end

    Rails.logger.info "Profanity list updated: #{results[:new_words_added]} added, #{results[:words_removed]} removed, total: #{results[:total_words]}"
    results
  end

  private

  def fetch_from_source(source)
    if source[:url].present?
      uri = URI(source[:url])
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 10
      response = http.get(uri.request_uri)
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parse_content(response.body, source)
    elsif source[:file].present?
      path = path_for_source_file(source[:file])
      return [] unless path && File.exist?(path)

      File.readlines(path).map(&:strip).reject(&:blank?)
    else
      []
    end
  end

  def path_for_source_file(file)
    return file if file.is_a?(Pathname) && file.absolute?
    Rails.root.join(file.to_s)
  end

  def parse_content(content, source)
    case source[:format]
    when :plain
      content.to_s.split("\n").map(&:strip).reject(&:blank?).reject { |w| w.start_with?("#") }
    when :json
      data = JSON.parse(content.to_s)
      path = source[:json_path]&.split(".") || []
      data = path.reduce(data) { |d, key| d[key] }
      data.is_a?(Array) ? data.map(&:to_s).map(&:strip).reject(&:blank?) : []
    else
      []
    end
  end

  def should_remove_old_words?(sources)
    url_sources = sources.count { |s| s[:enabled] && s[:url].present? }
    url_sources >= 2 && Rails.env.production?
  end
end
