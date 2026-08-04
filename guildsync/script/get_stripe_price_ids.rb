#!/usr/bin/env ruby
# Script to get Stripe price IDs from product IDs
# Usage: bundle exec rails runner script/get_stripe_price_ids.rb

require_relative '../config/environment'

# Product IDs you provided
PRODUCT_IDS = {
  'Basic Plan' => 'prod_TPwuFWJvkD8Se4',
  'Pro Plan' => 'prod_TPwvzW2Nfwn2ll',
  'Elite Plan' => 'prod_TPx8R0IFYg2Y0p'
}

puts "=" * 60
puts "Looking up Stripe Price IDs from Product IDs"
puts "=" * 60

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
    end
  rescue Stripe::StripeError => e
    puts "  ✗ Stripe error: #{e.message}"
  rescue => e
    puts "  ✗ Error: #{e.message}"
  end
end

puts "\n" + "=" * 60
puts "Price IDs Found:"
puts "=" * 60

if price_ids.any?
  price_ids.each do |plan_name, price_id|
    puts "#{plan_name}: #{price_id}"
    
    # Update the plan in the database
    plan = PricingPlan.find_by(name: plan_name)
    if plan
      plan.update!(stripe_price_id: price_id)
      puts "  ✓ Updated database"
    else
      puts "  ✗ Plan not found in database"
    end
  end
  
  puts "\n✓ All plans updated successfully!"
else
  puts "No price IDs found. Please check your Stripe dashboard."
end

puts "\nCurrent database status:"
PricingPlan.where(name: ['Basic Plan', 'Pro Plan', 'Elite Plan']).each do |plan|
  status = plan.stripe_price_id.present? ? "✓" : "✗"
  puts "  #{status} #{plan.name}: #{plan.stripe_price_id || 'NO PRICE ID'}"
end

