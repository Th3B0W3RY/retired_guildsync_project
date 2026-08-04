# frozen_string_literal: true

# Database connection cleanup for tests
# Ensures connections are properly closed after each test

RSpec.configure do |config|
  # Clean up database connections after each test
  # This helps prevent stranded connections when tests are interrupted
  # Note: RSpec's transactional fixtures handle transaction rollback automatically
  config.after(:each) do
    begin
      # Release connection back to pool (ActiveRecord 8.x uses connection_pool)
      # RSpec's transactional fixtures will handle transaction rollback
      ActiveRecord::Base.connection_pool.release_connection
    end
  end
  
  # Clean up on suite completion
  config.after(:suite) do
    begin
      ActiveRecord::Base.connection_pool.release_connection
      ActiveRecord::Base.connection_pool.disconnect!
    rescue => e
      # Ignore errors during final cleanup
    end
  end
end

