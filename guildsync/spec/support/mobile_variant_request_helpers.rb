# frozen_string_literal: true

# Shared User-Agent strings for request specs exercising `request.variant` / `*.html+mobile.erb`.
module MobileVariantRequestHelpers
  IPHONE_SAFARI_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
  ANDROID_CHROME_MOBILE_UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
  DESKTOP_CHROME_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  def mobile_user_agent_headers(user_agent = IPHONE_SAFARI_UA)
    { "User-Agent" => user_agent }
  end
end

RSpec.configure do |config|
  config.include MobileVariantRequestHelpers, type: :request
end
