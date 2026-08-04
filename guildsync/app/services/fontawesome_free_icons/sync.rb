# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module FontawesomeFreeIcons
  # Fetches Font Awesome Free metadata (icons.json) and upserts rows for reuse and admin picker validation.
  class Sync
    class Error < StandardError; end

    # npm @fortawesome/fontawesome-free no longer includes metadata/ on CDNs; Font-Awesome@6 matches frontend ^6.7.x.
    DEFAULT_URL = "https://cdn.jsdelivr.net/gh/FortAwesome/Font-Awesome@6/metadata/icons.json"

    def initialize(metadata_url: ENV.fetch("FONTAWESOME_FREE_METADATA_URL", DEFAULT_URL))
      @metadata_url = metadata_url
    end

    def call
      icons = fetch_icons_hash
      count = upsert_from_icons!(icons)
      { processed: count, icon_definitions: icons.size }
    end

    private

    def fetch_icons_hash
      uri = URI.parse(@metadata_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 60

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Font Awesome metadata HTTP #{response.code}: #{response.message}"
      end

      data = JSON.parse(response.body)
      raise Error, "Font Awesome metadata: expected JSON object" unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      raise Error, "Font Awesome metadata: invalid JSON (#{e.message})"
    end

    def upsert_from_icons!(icons_hash)
      rows = []
      timestamp = Time.current

      icons_hash.each do |icon_name, meta|
        next unless meta.is_a?(Hash)

        free_styles = Array(meta["free"]).map(&:to_s) & FontawesomeFreeIcon::STYLES
        next if free_styles.empty?

        icon_name = icon_name.to_s
        label = meta["label"].presence || icon_name.tr("-", " ").titleize

        free_styles.each do |style|
          rows << {
            style: style,
            icon_name: icon_name,
            label: label,
            created_at: timestamp,
            updated_at: timestamp
          }
        end
      end

      FontawesomeFreeIcon.transaction do
        rows.each_slice(1000) do |batch|
          FontawesomeFreeIcon.upsert_all(batch, unique_by: %i[style icon_name])
        end
      end

      rows.size
    end
  end
end
