# frozen_string_literal: true

# Configure Stripe API key
if Rails.env.test?
  # Use test key in test environment
  Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || 'sk_test_dummy_key_for_tests'
else
  # Load from environment variable or Rails credentials
  Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || Rails.application.credentials.dig(:stripe, :secret_key)
  
  if Stripe.api_key.blank?
    Rails.logger.warn "WARNING: Stripe API key not configured. Set STRIPE_SECRET_KEY environment variable."
  end
end

