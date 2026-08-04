# frozen_string_literal: true

require 'webmock/rspec'

RSpec.configure do |config|
  # Disable real HTTP requests in tests
  config.before(:each) do |example|
    next if example.metadata[:real_network]

    WebMock.disable_net_connect!(allow_localhost: true)
  end
end

