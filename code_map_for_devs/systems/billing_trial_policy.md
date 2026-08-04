# Billing::TrialPolicy

**Last updated:** 2026-04-06

**File:** `guildsync/app/services/billing/trial_policy.rb`  
**Rule:** Stripe `trial_period_days` applies **only** when the target `PricingPlan#name` is `Basic`. Upgraded/Elite checkouts bill immediately (no trial in subscription_data).

**Specs:** `spec/requests/billing_spec.rb` — portal Checkout and **`POST /billing/create_checkout_session`** examples use a **Basic** plan (or assert omission of `trial_period_days`) so expectations match **`Billing::TrialPolicy`** and **`billing_checkout_subscription_data`** (no duplicate trial when already trialing the same plan).

**Related:** [pricing_plans.md](pricing_plans.md) (**mega #222**), [billing_stripe_flow.md](../overall/billing_stripe_flow.md) (**mega #217**), [plan_entitlements.md](plan_entitlements.md), [overall/request_specs_and_gates.md](../overall/request_specs_and_gates.md) (**`billing_spec`** row).
