# frozen_string_literal: true

class GuildMember
  # Strong-parameter-style extraction without feeding raw user hashes into mass assignment.
  class ApiAttributes
    class << self
      def extract(raw, guild:, acting_user:)
        src = normalize_source(raw)
        attrs = {}
        assign_role!(attrs, src, guild: guild, acting_user: acting_user)
        assign_status!(attrs, src)
        attrs
      end

      private

      def normalize_source(raw)
        h =
          if raw.respond_to?(:to_unsafe_h)
            raw.to_unsafe_h
          elsif raw.respond_to?(:to_h)
            raw.to_h
          else
            {}
          end
        h.stringify_keys
      end

      def assign_role!(attrs, src, guild:, acting_user:)
        return unless src.key?("role")

        r = src["role"].to_s
        return unless GuildMember.roles.key?(r)
        return if r == "owner" && !guild_owner?(guild, acting_user)

        attrs[:role] = r
      end

      def assign_status!(attrs, src)
        return unless src.key?("status")

        s = src["status"].to_s
        return unless GuildMember.statuses.key?(s)

        attrs[:status] = s
      end

      def guild_owner?(guild, acting_user)
        acting_user.present? && guild&.owner_id == acting_user.id
      end
    end
  end
end
