# frozen_string_literal: true

module Guildsync
  # OS service names passed to systemctl/net/brew must be tightly constrained.
  class PostgresServiceName
    Invalid = Class.new(StandardError)

    PATTERN = /\A[a-zA-Z0-9_.@-]+\z/.freeze
    MAX_LENGTH = 128

    class << self
      def sanitize!(name)
        s = name.to_s.strip
        raise Invalid, "blank service name" if s.blank?
        raise Invalid, "service name too long" if s.length > MAX_LENGTH
        raise Invalid, "invalid service name" unless s.match?(PATTERN)

        s
      end
    end
  end
end
