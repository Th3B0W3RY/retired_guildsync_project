# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    next unless ActiveRecord::Base.connection.data_source_exists?(:landing_comparison_tables)

    LandingCompare::SeedDefaults.seed!
  end
end
