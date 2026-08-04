#!/usr/bin/env ruby
# Sync Stripe price IDs and display prices from a products CSV (product IDs).
# CSV columns: id, Name, ... (id = Stripe product id, Name e.g. "Basic Plan - Monthly")
# Usage: bundle exec rails runner script/sync_stripe_prices_from_products_csv.rb [path/to/products.csv]
# Default path: script/data/products.csv or ENV['STRIPE_PRODUCTS_CSV']

require_relative "../config/environment"

csv_path = ARGV[0] || ENV["STRIPE_PRODUCTS_CSV"] || File.expand_path("data/products.csv", __dir__)

unless ENV["STRIPE_SECRET_KEY"].present? || Rails.application.credentials.dig(:stripe, :secret_key)
  puts "ERROR: Set STRIPE_SECRET_KEY or stripe secret in credentials."
  exit 1
end

Stripe.api_key = ENV["STRIPE_SECRET_KEY"] || Rails.application.credentials.dig(:stripe, :secret_key)

# Parse CSV: id, Name
require "csv"
rows = []
File.open(csv_path, "r") do |f|
  CSV.foreach(f, headers: true) do |row|
    next if row["id"].to_s.strip.empty?
    rows << { product_id: row["id"].strip, name: row["Name"].to_s.strip }
  end
end

# Map CSV name -> plan name and interval: "Basic Plan - Monthly" -> ["Basic", :month], "Elite Plan - Annual" -> ["Elite", :year]
def parse_product_name(name)
  return nil unless name.present?
  if name =~ /\A(.+?)\s+Plan\s+-\s+Monthly\z/i
    [ $1.strip, :month ]
  elsif name =~ /\A(.+?)\s+Plan\s+-\s+Annual\z/i
    [ $1.strip, :year ]
  else
    nil
  end
end

# Collect price_id and display per (plan_name, interval)
updates = {} # plan_name => { stripe_price_id:, price_display:, stripe_price_id_annual:, price_display_annual: }

rows.each do |row|
  parsed = parse_product_name(row[:name])
  next unless parsed
  plan_name, interval = parsed
  product_id = row[:product_id]
  next unless product_id.start_with?("prod_")

  prices = Stripe::Price.list(product: product_id, active: true, limit: 10)
  price = prices.data.first
  unless price
    puts "  ✗ No price for product #{product_id} (#{row[:name]})"
    next
  end

  amount = price.unit_amount ? (price.unit_amount / 100.0) : 0
  currency = (price.currency || "usd").upcase
  display = "$#{format('%.2f', amount)}"

  updates[plan_name] ||= {}
  if interval == :month
    updates[plan_name][:stripe_price_id] = price.id
    updates[plan_name][:price_display] = display
  else
    updates[plan_name][:stripe_price_id_annual] = price.id
    updates[plan_name][:price_display_annual] = display
  end
  puts "  #{plan_name} #{interval}: #{price.id} #{display} #{currency}"
end

puts "\nUpdating pricing_plans..."
updates.each do |plan_name, attrs|
  plan = PricingPlan.find_by(name: plan_name)
  unless plan
    puts "  ✗ Plan '#{plan_name}' not found"
    next
  end
  # Only update attributes we have (don't clear annual if this row was only monthly)
  to_update = attrs.slice(:stripe_price_id, :price_display, :stripe_price_id_annual, :price_display_annual).compact
  plan.update!(to_update) if to_update.any?
  puts "  ✓ #{plan_name}"
end

puts "\nDone. Current plans:"
PricingPlan.where(name: %w[Basic Upgraded Elite]).each do |p|
  puts "  #{p.name}: monthly=#{p.stripe_price_id} #{p.price_display} | annual=#{p.stripe_price_id_annual} #{p.price_display_annual}"
end
