# frozen_string_literal: true

module GearSnapshots
  # Persists user edits to +GearSnapshot#data+ (update labels/values, remove rows, restore after undo).
  class UpdateExtractedData
    MAX_KEY_LENGTH = 300

    class Result
      attr_reader :snapshot, :code, :new_stat_key

      def initialize(ok:, snapshot: nil, code: nil, new_stat_key: nil)
        @ok = ok
        @snapshot = snapshot
        @code = code
        @new_stat_key = new_stat_key
      end

      def success?
        @ok
      end

      def self.ok(snapshot, new_stat_key: nil)
        new(ok: true, snapshot: snapshot, new_stat_key: new_stat_key)
      end

      def self.fail(code)
        new(ok: false, code: code)
      end
    end

    class << self
      def call(snapshot:, operation:, stat_key:, stat_value: nil, stat_label: nil)
        new(
          snapshot: snapshot,
          operation: operation,
          stat_key: stat_key,
          stat_value: stat_value,
          stat_label: stat_label
        ).call
      end
    end

    def initialize(snapshot:, operation:, stat_key:, stat_value: nil, stat_label: nil)
      @snapshot = snapshot
      @operation = operation.to_s.strip.downcase
      @stat_key = stat_key.to_s
      @stat_value = stat_value
      @stat_label = stat_label
    end

    def call
      return Result.fail(:blank_key) if @stat_key.blank?
      return Result.fail(:key_too_long) if @stat_key.length > MAX_KEY_LENGTH
      return Result.fail(:invalid_key) if @stat_key.match?(/[\u0000-\u001F]/)

      data = normalized_hash

      case @operation
      when "remove"
        remove_from(data)
      when "restore"
        restore_into(data)
      when "update"
        update_row(data)
      else
        Result.fail(:unknown_operation)
      end
    rescue ActiveRecord::RecordInvalid
      Result.fail(:invalid_record)
    end

    private

    def normalized_hash
      d = @snapshot.data
      return {} unless d.is_a?(Hash)

      d.stringify_keys
    end

    def remove_from(data)
      return Result.fail(:missing_key) unless data.key?(@stat_key)

      new_data = data.except(@stat_key)
      @snapshot.update!(data: new_data)
      Result.ok(@snapshot.reload)
    end

    def restore_into(data)
      return Result.fail(:key_exists) if data.key?(@stat_key)

      value, err = coerce_restore_value(@stat_value)
      return Result.fail(err) if err

      new_data = data.merge(@stat_key => value)
      @snapshot.update!(data: new_data)
      Result.ok(@snapshot.reload)
    end

    def update_row(data)
      return Result.fail(:missing_label) if @stat_label.nil?

      return Result.fail(:missing_key) unless data.key?(@stat_key)

      new_key = @stat_label.to_s.strip
      return Result.fail(:blank_key) if new_key.blank?
      return Result.fail(:key_too_long) if new_key.length > MAX_KEY_LENGTH
      return Result.fail(:invalid_key) if new_key.match?(/[\u0000-\u001F]/)

      new_val, err = coerce_restore_value(@stat_value)
      return Result.fail(err) if err

      if new_key != @stat_key && data.key?(new_key)
        return Result.fail(:key_exists)
      end

      new_data = data.except(@stat_key).merge(new_key => new_val)
      @snapshot.update!(data: new_data)
      Result.ok(@snapshot.reload, new_stat_key: new_key)
    end

    def coerce_restore_value(raw)
      case raw
      when nil
        [nil, nil]
      when String, Numeric, TrueClass, FalseClass
        [raw, nil]
      when Hash, Array
        [nil, :complex_type]
      else
        [nil, :unsupported_type]
      end
    end
  end
end
