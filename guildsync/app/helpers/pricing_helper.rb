module PricingHelper
  # Fetch pricing plans from database - falls back to default if none exist
  def pricing_plans
    # Guard against missing table (e.g., during migrations)
    return default_pricing_plans unless defined?(PricingPlan) && PricingPlan.table_exists?

    plans = PricingPlan.active.ordered

    # If no plans exist in database, return default structure for backward compatibility
    return default_pricing_plans if plans.empty?

    # Convert database records to hash format for view compatibility
    plans.map do |plan|
      is_paid_plan = !plan.free_tier?

      # Use plan's cta_text if present, otherwise fallback
      cta_text = if plan.cta_text.present?
        plan.cta_text
      else
        is_paid_plan ? "Continue" : "Get Started"
      end

      {
        id: plan.id,
        name: plan.name,
        price: plan.formatted_price,
        period: plan.period,
        description: plan.description,
        features: plan.features || [],
        cta_text: cta_text,
        cta_path: plan.cta_path,
        popular: plan.popular,
        trial_text: is_paid_plan ? "Trial begins after MFA verification" : nil
      }
    end
  end

  private

  # Default plans structure (for backward compatibility or initial setup)
  # Note: These don't have IDs since they're fallbacks - real plans should be in database
  def default_pricing_plans
    [
      {
        id: nil, # Will be set when plan is created in database
        name: "Basic Plan",
        price: "$8.99",
        period: "per month",
        description: "For small communities",
        features: [
          "Up to 10 guilds",
          "Up to 50 members per guild",
          "Advanced event management",
          "Event reminders",
          "Email support"
        ],
        cta_text: "Continue",
        cta_path: "/sign_up",
        popular: false,
        trial_text: "Trial begins after MFA verification"
      },
      {
        id: nil,
        name: "Pro Plan",
        price: "$14.99",
        period: "per month",
        description: "For growing communities",
        features: [
          "Unlimited guilds",
          "Up to 200 members per guild",
          "Advanced analytics",
          "Custom event types",
          "API access"
        ],
        cta_text: "Continue",
        cta_path: "/sign_up",
        popular: true,
        trial_text: "Trial begins after MFA verification"
      },
      {
        id: nil,
        name: "Elite Plan",
        price: "$24.99",
        period: "per month",
        description: "For large organizations",
        features: [
          "Unlimited guilds",
          "Unlimited members per guild",
          "Advanced analytics",
          "Custom event types",
          "API access",
          "Priority support",
          "Custom integrations",
          "Advanced security features"
        ],
        cta_text: "Continue",
        cta_path: "/sign_up",
        popular: false,
        trial_text: "Trial begins after MFA verification"
      },
      {
        id: nil,
        name: "Free",
        price: "$0",
        period: "forever",
        description: "Perfect for getting started",
        features: [
          "Up to 1 guild",
          "Up to 50 members per guild",
          "Basic event management",
          "Community support"
        ],
        cta_text: "Get Started",
        cta_path: "/sign_up",
        popular: false,
        trial_text: nil # Free plan has no trial
      }
    ]
  end
end
