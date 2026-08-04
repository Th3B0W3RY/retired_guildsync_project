# frozen_string_literal: true

module Guildsync
  # Resolves GUILDSYNC_PYTHON_CMD (or default) to a single argv[0] suitable for Open3/exec:
  # no shell, no metacharacters, no path traversal. Absolute paths must exist and be executable.
  class SafePythonExecutable
    InvalidExecutable = Class.new(StandardError)

    TOKEN_PATTERN = /\A[A-Za-z0-9._-]+\z/.freeze
    PATHLIKE_PATTERN = /\A[A-Za-z0-9._\/\\:-]+\z/.freeze

    class << self
      def resolve!(raw)
        cmd = raw.to_s.strip
        raise InvalidExecutable, "python command is blank" if cmd.blank?
        raise InvalidExecutable, "invalid python command" unless cmd.match?(PATHLIKE_PATTERN)
        raise InvalidExecutable, "path traversal in python command" if cmd.include?("..")

        resolve_pathlike!(cmd)
      end

      private

      def resolve_pathlike!(cmd)
        if path_like_command?(cmd)
          expanded = File.expand_path(cmd)
          raise InvalidExecutable, "python not found at #{expanded}" unless File.exist?(expanded)
          raise InvalidExecutable, "python is not executable at #{expanded}" unless File.executable?(expanded)

          expanded
        else
          raise InvalidExecutable, "invalid python command name" unless cmd.match?(TOKEN_PATTERN)

          cmd
        end
      end

      def path_like_command?(cmd)
        cmd.include?("/") || cmd.include?("\\") || windows_drive_path?(cmd)
      end

      def windows_drive_path?(cmd)
        Gem.win_platform? && cmd.match?(/\A[A-Za-z]:/)
      end
    end
  end
end
