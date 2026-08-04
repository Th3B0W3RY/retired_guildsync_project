namespace :subscriptions do
  desc "Backfill Free subscriptions for existing users without current subscriptions"
  task backfill_free: :environment do
    free_plan = PricingPlan.find_by(name: "Free")

    unless free_plan
      puts "ERROR: Free pricing plan not found. Please run 'rails db:seed' first."
      exit 1
    end

    puts "Checking all users for current subscriptions..."

    count = 0
    User.find_each do |user|
      # Check if user has a current subscription (active or trialing)
      unless user.subscriptions.current.exists?
        user.ensure_free_plan_subscription
        count += 1
        print "."
      end
    end

    if count == 0
      puts "\n✓ All users already have current subscriptions. Nothing to do."
    else
      puts "\n✓ Successfully created Free subscriptions for #{count} users."
    end
  end
end
