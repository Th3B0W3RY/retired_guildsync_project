#!/usr/bin/env ruby
# Quick script to set Stripe price IDs
# 
# IMPORTANT: You need to get the actual PRICE IDs (price_xxxxx) from your Stripe dashboard:
# 1. Go to Stripe Dashboard > Products
# 2. Click on each product (Basic, Upgraded, Elite)
# 3. Find the monthly recurring price and copy its ID (starts with price_)
#
# Then update the PRICE_IDS hash below and run:
# bundle exec rails runner script/set_stripe_prices.rb

# Paid plans: Basic $12, Upgraded $16, Elite $25 (Free has no Stripe price)
PRICE_IDS = {
  'Basic' => ENV['STRIPE_BASIC_PRICE_ID'],       # $12/mo
  'Upgraded' => ENV['STRIPE_UPGRADED_PRICE_ID'], # $16/mo
  'Elite' => ENV['STRIPE_ELITE_PRICE_ID']        # $25/mo
}

puts "=" * 60
puts "Setting Stripe Price IDs"
puts "=" * 60

updated = 0
PRICE_IDS.each do |plan_name, price_id|
  if price_id.blank?
    puts "  ⚠ Skipping #{plan_name} - no price ID provided (set STRIPE_*_PRICE_ID in .env)"
    next
  end
  
  plan = PricingPlan.find_by(name: plan_name)
  if plan
    plan.update!(stripe_price_id: price_id)
    puts "  ✓ Updated #{plan_name} with price ID: #{price_id}"
    updated += 1
  else
    puts "  ✗ Plan '#{plan_name}' not found"
  end
end

puts "\n" + "=" * 60
puts "Updated #{updated} plan(s)"
puts "=" * 60

puts "\nCurrent status:"
PricingPlan.where(name: [ 'Basic', 'Upgraded', 'Elite' ]).each do |plan|
  status = plan.stripe_price_id.present? && plan.stripe_price_id != 'price_placeholder' ? "✓" : "✗"
  puts "  #{status} #{plan.name}: #{plan.stripe_price_id || 'NO PRICE ID'}"
end

if updated == 0
  puts "\n⚠ No plans updated. Please add the actual Stripe price IDs to the PRICE_IDS hash in this script."
end

