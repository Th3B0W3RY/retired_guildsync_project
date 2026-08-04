# Script to update pricing plans with Stripe price IDs
# Usage: bundle exec rails runner lib/update_stripe_price_ids.rb

# Map of plan names to Stripe price IDs
# NOTE: These are PRICE IDs (price_xxx), not product IDs (prod_xxx)
# You need to get these from your Stripe dashboard or API
# 3 plans: Free (no Stripe), Standard $10, Elite $20
STRIPE_PRICE_IDS = {
  'Standard' => ENV['STRIPE_STANDARD_PRICE_ID'],
  'Elite' => ENV['STRIPE_ELITE_PRICE_ID']
}

STRIPE_PRODUCT_IDS = {
  'Standard' => nil,  # Optional: set if you have product IDs to look up
  'Elite' => nil
}

def lookup_price_ids_from_products
  puts "Looking up price IDs from product IDs..."
  price_ids = {}
  
  STRIPE_PRODUCT_IDS.each do |plan_name, product_id|
    begin
      product = Stripe::Product.retrieve(product_id)
      prices = Stripe::Price.list(product: product_id, active: true, limit: 10)
      
      # Find the recurring monthly price
      monthly_price = prices.data.find { |p| p.recurring&.interval == 'month' }
      
      if monthly_price
        price_ids[plan_name] = monthly_price.id
        puts "  ✓ #{plan_name}: Found price ID #{monthly_price.id}"
      else
        puts "  ✗ #{plan_name}: No monthly price found for product #{product_id}"
      end
    rescue Stripe::StripeError => e
      puts "  ✗ #{plan_name}: Error looking up product #{product_id}: #{e.message}"
    end
  end
  
  price_ids
end

# Main execution
puts "=" * 60
puts "Updating Stripe Price IDs for Pricing Plans"
puts "=" * 60

# Try to look up price IDs from product IDs
price_ids = lookup_price_ids_from_products

# Merge with any manually specified price IDs
STRIPE_PRICE_IDS.each do |plan_name, price_id|
  price_ids[plan_name] = price_id if price_id.present?
end

# Update the plans
updated_count = 0
price_ids.each do |plan_name, price_id|
  next unless price_id.present?
  
  plan = PricingPlan.find_by(name: plan_name)
  if plan
    plan.update(stripe_price_id: price_id)
    puts "  ✓ Updated #{plan_name} with price ID: #{price_id}"
    updated_count += 1
  else
    puts "  ✗ Plan '#{plan_name}' not found"
  end
end

puts "=" * 60
puts "Updated #{updated_count} plan(s)"
puts "=" * 60

# Show current status
puts "\nCurrent plan status:"
PricingPlan.where(name: ['Standard', 'Elite']).each do |plan|
  status = plan.stripe_price_id.present? ? "✓" : "✗"
  puts "  #{status} #{plan.name}: #{plan.stripe_price_id || 'NO PRICE ID'}"
end

