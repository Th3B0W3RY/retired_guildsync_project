# frozen_string_literal: true

module Guildsync
  # Validates admin-configured URLs before redirect_to(..., allow_other_host: true).
  class ExternalRedirectUrl
    Invalid = Class.new(StandardError)

    class << self
      def build!(url_string)
        s = url_string.to_s.strip
        raise Invalid if s.blank?
        raise Invalid if s.match?(/[\r\n\\]/)

        uri =
          begin
            URI.parse(s)
          rescue URI::InvalidURIError
            raise Invalid
          end
        raise Invalid unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        raise Invalid if uri.host.blank?

        uri.to_s
      end
    end
  end
end
