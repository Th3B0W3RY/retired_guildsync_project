# frozen_string_literal: true

module GuildSync
  module Migrations
    # Pure helper: finds migration filename version prefixes that appear more than once.
    # Rails requires unique versions; duplicates break db:schema:load and db:test:prepare.
    class DuplicateVersionDetector
      def self.duplicate_versions(migrate_dir = Rails.root.join("db/migrate"))
        basenames = Dir[migrate_dir.join("*.rb")].map { |path| File.basename(path) }
        versions = basenames.map { |name| name.split("_", 2).first }
        versions.tally.select { |_, count| count > 1 }.keys.sort
      end
    end
  end
end
