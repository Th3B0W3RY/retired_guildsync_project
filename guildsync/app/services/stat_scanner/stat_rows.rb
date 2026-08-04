# frozen_string_literal: true

module StatScanner
  # Normalizes snapshot JSON into ordered rows for UI rendering.
  # Each key/value in +data+ becomes one row (dynamic list — no hardcoded stat names).
  # Order follows Hash insertion order (same as UniversalStatParser output).
  class StatRows
    # +key+ is the exact hash key in +GearSnapshot#data+ (for PATCH). +label+ is display text.
    Row = Struct.new(:key, :label, :value, :raw_value, keyword_init: true)

    class << self
      def from_data(data)
        return [] if data.nil?

        unless data.is_a?(Hash)
          blob = data.to_s.strip.presence || "—"
          return [Row.new(key: "", label: I18n.t("guilds.member_stats.unparsed_label"), value: blob, raw_value: data)]
        end

        data.each_with_object([]) do |(k, v), rows|
          key_str = k.nil? ? "" : k.to_s
          next if key_str.strip.empty? && v.blank?

          val = format_value(v)
          rows << Row.new(
            key: key_str,
            label: key_str.strip.presence || I18n.t("guilds.member_stats.unnamed_stat"),
            value: val,
            raw_value: v
          )
        end
      end

      private

      def format_value(v)
        return "—" if v.nil?

        s = case v
            when String then v
            when Numeric then v.to_s
            when TrueClass, FalseClass then v.to_s
            else v.to_s
            end
        s = s.strip
        s.presence || "—"
      end
    end
  end
end
