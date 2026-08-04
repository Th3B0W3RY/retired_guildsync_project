#!/usr/bin/env ruby
# Quick script to update Stripe price IDs for pricing plans
# Usage: bundle exec rails runner script/update_stripe_prices.rb

# IMPORTANT: Replace these with your actual Stripe PRICE IDs (price_xxxxx)
# You can find these in your Stripe Dashboard > Products > [Product] > Pricing
# Or by running: Stripe::Price.list(product: 'prod_xxxxx', active: true)

PRICE_IDS = {
  'Basic Plan' => nil,  # TODO: Replace with actual price ID like 'price_1ABC123...'
  'Pro Plan' => nil,    # TODO: Replace with actual price ID like 'price_1DEF456...'
  'Elite Plan' => nil   # TODO: Replace with actual price ID like 'price_1GHI789...'
}

puts "=" * 60
puts "Updating Stripe Price IDs"
puts "=" * 60

PRICE_IDS.each do |plan_name, price_id|
  if price_id.nil?
    puts "  ⚠ Skipping #{plan_name} - no price ID provided"
    next
  end
  
  plan = PricingPlan.find_by(name: plan_name)
  if plan
    plan.update!(stripe_price_id: price_id)
    puts "  ✓ Updated #{plan_name} with price ID: #{price_id}"
  else
    puts "  ✗ Plan '#{plan_name}' not found"
  end
end

puts "\nCurrent status:"
PricingPlan.where(name: ['Basic Plan', 'Pro Plan', 'Elite Plan']).each do |plan|
  status = plan.stripe_price_id.present? ? "✓" : "✗"
  puts "  #{status} #{plan.name}: #{plan.stripe_price_id || 'NO PRICE ID'}"
end

