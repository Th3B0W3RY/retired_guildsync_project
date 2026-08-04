# frozen_string_literal: true

module LandingMarketing
  module Snapshot
    module Paths
      module_function

      def default_file
        Rails.root.join("config/landing/marketing_snapshot.yml")
      end
    end
  end
end
