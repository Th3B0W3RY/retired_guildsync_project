require "net/http"
require "uri"
require "json"

class DiscordApi
  def self.send_followup(application_id, interaction_token, content, flags: 64)
    return unless application_id && interaction_token && content

    uri = URI("https://discord.com/api/v10/webhooks/#{application_id}/#{interaction_token}")

    body = {
      content: content,
      flags: flags # 64 = ephemeral
    }

    begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body.to_json
        response = http.request(request)
        
        unless response.code.to_i == 200 || response.code.to_i == 204
          Rails.logger.error "Discord follow-up failed: #{response.code} - #{response.body}"
        end
      end
    rescue => e
      Rails.logger.error "Failed to send Discord follow-up: #{e.message}"
    end
  end
end

