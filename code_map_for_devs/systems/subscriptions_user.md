# Subscriptions and User

**Last updated:** 2026-04-06

## Models

- **`guildsync/app/models/subscription.rb`** — `status` enum (active, canceled, expired, trialing); scopes `current` (active + trialing).
- **`guildsync/app/models/user.rb`** — `has_many :subscriptions`, `has_one :current_subscription` (through `current` scope).

## Key User APIs (billing access)

| Method | Role |
|--------|------|
| `current_plan` / `current_plan!` | Resolves `PricingPlan` via current subscription; may ensure Free row exists for legacy users. |
| `plan_allows?(feature)` | Delegates to `PlanEntitlementService` (see `systems/plan_entitlements.md`). |
| `subscribe_to_plan!(plan, ...)` | Cancels other **active** subs; creates new row (active or trialing). |
| `trial_active?`, `subscribed?`, `access_allowed?` | Alliance and paid-feature gates combine these with `current_plan.free?`. |
| `create_trial_at_signup!(plan)` | New-user Basic trial only (guards in method). |
| `start_trial_from_free!(plan)` | Pricing / signup flows from Free → trialing Basic. |
| `switch_plan_during_trial!(new_plan)` | While trialing. |
| `downgrade_to_free_during_trial!` | Frees user mid-trial; triggers `FreePlanDowngradeSideEffects` where applicable. |
| `activate_free_plan!` / `convert_expired_trial_to_free!` | Stripe + manual paths; downgrade side effects on alliance, etc. |
| `has_used_trial?` | Prevents re-trial abuse (includes forfeited / ended trials). |

## Failure modes

- Missing `PricingPlan` row for subscription → entitlement matrix miss; see `plan_entitlements.yml`.
- Webhook and controller paths must stay consistent on **trialing** vs **active** for `access_allowed?`.

## Specs

- `spec/models/user_spec.rb` (trial, subscribe, downgrade).
- `spec/requests/plan_entitlements_matrix_spec.rb` (HTTP gates vs plan name).
- `spec/services/subscription_cancellation_service_spec.rb` — cancel/resume paths used by **`BillingController`** and **`Admin::GuildOwnershipTransferService`** (optional handover billing).
- `spec/requests/billing_spec.rb` — **`POST /billing/cancel_subscription`** / **`resume_subscription`** (HTML + JSON vs **`require_stripe_subscription!`**).

**Related:** [pricing_plans.md](pricing_plans.md) (**mega #222**), [stripe_webhooks.md](stripe_webhooks.md) (**mega #126**; cross-ref **mega #217**), [plan_entitlements.md](plan_entitlements.md), [free_downgrade_alliance.md](free_downgrade_alliance.md), [billing_trial_policy.md](billing_trial_policy.md); [billing_stripe_flow.md](../overall/billing_stripe_flow.md) (**mega #217**); [overall/data_model_core.md](../overall/data_model_core.md) (**mega #209** — **`Subscription`** in ER / join-model hub).
