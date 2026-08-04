#!/usr/bin/env ruby
# Script to fetch Stripe price IDs from product IDs and update the database
# Usage: bundle exec rails runner script/fetch_and_set_stripe_prices.rb

require_relative '../config/environment'

# Product IDs you provided
PRODUCT_IDS = {
  'Basic Plan' => 'prod_TPwuFWJvkD8Se4',
  'Pro Plan' => 'prod_TPwvzW2Nfwn2ll',
  'Elite Plan' => 'prod_TPx8R0IFYg2Y0p'
}

puts "=" * 60
puts "Fetching Stripe Price IDs from Product IDs"
puts "=" * 60

# Check if Stripe API key is configured
unless ENV['STRIPE_SECRET_KEY'].present? || Rails.application.credentials.dig(:stripe, :secret_key)
  puts "ERROR: Stripe API key not found!"
  puts "Please set STRIPE_SECRET_KEY environment variable or configure in credentials"
  exit 1
end

# Set Stripe API key if not already set
Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || Rails.application.credentials.dig(:stripe, :secret_key)

price_ids = {}

PRODUCT_IDS.each do |plan_name, product_id|
  begin
    puts "\nLooking up #{plan_name} (Product: #{product_id})..."

    # Get all prices for this product
    prices = Stripe::Price.list(product: product_id, active: true, limit: 100)

    if prices.data.empty?
      puts "  ✗ No prices found for product #{product_id}"
      next
    end

    # Find the recurring monthly price
    monthly_price = prices.data.find { |p| p.recurring && p.recurring.interval == 'month' }

    if monthly_price
      price_ids[plan_name] = monthly_price.id
      puts "  ✓ Found monthly price ID: #{monthly_price.id}"
      puts "     Amount: $#{monthly_price.unit_amount / 100.0} #{monthly_price.currency.upcase}"
    else
      # If no monthly price, show all available prices
      puts "  ⚠ No monthly recurring price found. Available prices:"
      prices.data.each do |price|
        interval = price.recurring ? "#{price.recurring.interval}ly" : "one-time"
        puts "     - #{price.id}: $#{price.unit_amount / 100.0} #{price.currency.upcase} (#{interval})"
      end
      # Use the first price if available
      if prices.data.any?
        price_ids[plan_name] = prices.data.first.id
        puts "  → Using first available price: #{prices.data.first.id}"
      end
    end
  rescue Stripe::StripeError => e
    puts "  ✗ Stripe error: #{e.message}"
  rescue => e
    puts "  ✗ Error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end

puts "\n" + "=" * 60
puts "Updating Database"
puts "=" * 60

if price_ids.any?
  updated_count = 0
  price_ids.each do |plan_name, price_id|
    plan = PricingPlan.find_by(name: plan_name)
    if plan
      plan.update!(stripe_price_id: price_id)
      puts "  ✓ Updated #{plan_name} with price ID: #{price_id}"
      updated_count += 1
    else
      puts "  ✗ Plan '#{plan_name}' not found in database"
    end
  end

  puts "\n✓ Successfully updated #{updated_count} plan(s)!"
else
  puts "\n✗ No price IDs found. Please check your Stripe dashboard."
end

puts "\n" + "=" * 60
puts "Current Database Status"
puts "=" * 60
PricingPlan.where(name: [ 'Basic Plan', 'Pro Plan', 'Elite Plan' ]).each do |plan|
  status = plan.stripe_price_id.present? && plan.stripe_price_id != 'price_placeholder' ? "✓" : "✗"
  puts "  #{status} #{plan.name}: #{plan.stripe_price_id || 'NO PRICE ID'}"
end
