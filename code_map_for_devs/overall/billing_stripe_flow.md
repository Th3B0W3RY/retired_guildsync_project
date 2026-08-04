# Billing and Stripe

**Last updated:** 2026-04-06 (**mega #217** — Lane C; **`billing_spec`** **`GET /billing`** **`support_center_url`** — **changelog 275**; webhook audit remains **mega #126**)

## `BillingController` (web + JSON)

**Path:** `guildsync/app/controllers/billing_controller.rb`

| Concern | Detail |
|---------|--------|
| **Auth** | **`authenticate_user!`** on all actions. |
| **JSON vs HTML** | **`detect_json_format`** runs before **`create_portal_session`**, **`checkout`**, **`change_plan`**, **`preview_plan_change`**, **`cancel_subscription`**, **`resume_subscription`**. Sets **`request.format`** from **`request.format.json?`**, **`.json`** in path, **`Accept: application/json`**, or **`params[:format] == "json"`** so **`respond_to`** / **`render json:`** paths match **`billing_spec`** examples without a **`.json`** suffix everywhere. |
| **Stripe subscription required** | **`require_stripe_subscription!`** for **`change_plan`**, **`preview_plan_change`**, **`cancel_subscription`**, **`resume_subscription`**. Missing **`stripe_subscription_id`** on current subscription → **422** JSON **`controllers.billing.no_stripe_subscription`** / HTML redirect + alert. |
| **`#show`** | Billing dashboard; **`session_id`** (Stripe return) → **`handle_checkout_success`**; loads **`@subscription`**, **`@pricing_plan`**, active non-Free **`@plans`**, trial countdown, **`load_stripe_billing_extras`** (Stripe customer balance, **`cancel_at_period_end`**, period end). **`billing/show`** “contact billing team” uses **`support_center_url`** (**`billing_spec`** **changelog 275**). |
| **`#change_plan`** | **`PricingPlan.active.find_by(id: params[:plan_id])`** — missing/inactive → **`respond_to_change`** with **`controllers.billing.plan_not_found`** (**mega** coverage in **`billing_spec`**). Else **`SubscriptionPlanChangeService.call`** (**user**, **target_plan**, **interval**). |
| **`#preview_plan_change`** | Same plan lookup; **404** JSON / HTML alert for missing plan. **`SubscriptionPlanPreviewService.call`** → JSON **`amount_due`**, **`currency`**, **`formatted`** (or empty nulls). |
| **`#cancel_subscription`** / **`#resume_subscription`** | **`SubscriptionCancellationService.call`** / **`.resume!`**; success message keys vary by cancel mode (**refund**, **period_end**, immediate). |
| **`#create_portal_session`** | **`respond_to`**: JSON delegates to **`portal`** (**mega #120**); HTML path picks plan, opens Stripe Billing Portal or Checkout per customer + price availability (**security events** logged). |
| **`#checkout`** | JSON-only path: blocks non-trial users with existing **`stripe_subscription_id`**, requires **`price_id`**, ensures Stripe customer, applies **`Billing::TrialPolicy.stripe_trial_period_days`** via **`subscription_data`** (except requests add-on price). **mega #120** error keys. |
| **Success return** | **`handle_checkout_success`** validates session metadata vs **`current_user`**, syncs **`Subscription`** from Stripe; redirect notice **`controllers.billing.checkout_success`** (**mega #121**). |

**Related megas:** **#120** (checkout + portal JSON), **#121** (checkout success flash), **#126** (webhook **`head`** only).

## Plan change, preview, cancellation (services)

- **`SubscriptionPlanChangeService`** (`guildsync/app/services/subscription_plan_change_service.rb`) — Validates paid target plan, resolves **`price_id_for_interval`**, loads Stripe subscription, applies **`proration_behavior_between`** (upgrade vs downgrade), updates subscription item price. Returns **`Result`** **`ok`/`error`** strings consumed by **`respond_to_change`**.
- **`SubscriptionPlanPreviewService`** (`guildsync/app/services/subscription_plan_preview_service.rb`) — **`Stripe::Invoice.upcoming`** with proration behavior from **`SubscriptionPlanChangeService.proration_behavior_between`**; rescues **`Stripe::StripeError`** → **`nil`** (controller renders empty preview JSON).
- **`SubscriptionCancellationService`** — See **Spec pointers** below and **`spec/services/subscription_cancellation_service_spec.rb`** (modes: refund, period end, immediate, resume).

## Data model

- **`PricingPlan`** — Name, limits (`max_guilds`, `max_members_per_guild`), display fields. Seeded/updated via `lib/pricing_plan_initializer.rb` (ENV for Stripe price IDs where configured).
- **`Subscription`** — Belongs to `User`, `PricingPlan`; status (`active`, `trialing`, `canceled`, etc.), `trial_ends_at`, Stripe IDs.
- **`User`** — `stripe_customer_id`, `stripe_subscription_id`, billing helper methods (`current_plan`, `trial_active?`, `activate_free_plan!`, etc.).

## User-facing checkout

| Entry | Controller / action | Notes |
|-------|---------------------|--------|
| Pricing page | `PricingController` | `redirect_to_stripe_checkout!`, plan selection |
| Billing portal | `BillingController` | Customer portal session |
| Legacy | `SubscriptionsController` | Older paths still wired in routes |

## Trial policy

- **`Billing::TrialPolicy`** — **Only Basic** may receive Stripe `trial_period_days` (14 days in product spec). Upgraded/Elite: no trial from app.
- **i18n:** `pricing.upgrade.free_trial_box` and `pricing.public_pricing` (`trial_included`, `free_plan_intro`, `trial_info`) state Basic-only trial in **all 10 locales** (aligned with policy).
- **`User#has_used_trial?`** — True if `trial_ends_at` is past, or a **canceled** subscription still had a future `trial_ends_at` (forfeited mid-trial), so users cannot chain trials.
- **`User#downgrade_to_free_during_trial!`** — After `switch_plan_during_trial!(Free)`, runs **`FreePlanDowngradeSideEffects`** (same as full free activation) so alliances drop immediately.
- **Post-signup flow** — `SignupPlanChoicesController`, `session[:post_signup_paid_plan_id]`, MFA redirect after registration.

## Webhooks (critical)

- **`Stripe::WebhooksController`** — Raw body + `Stripe-Signature` header → `Stripe::Webhook.construct_event(payload, sig, secret)`.
- **HTTP contract (mega audit):** Responses are **`head` only** (`:ok`, `:unauthorized`, `:bad_request`). Stripe does not display a body to end users — **no i18n surface** on this endpoint; English log lines remain operator-facing.
- **Misconfiguration:** If `STRIPE_WEBHOOK_SECRET` missing, controller logs and returns **401** without processing the payload.
- **`StripeWebhookProcessor`** — Maps events to `Subscription` updates, `beta_features_enabled` for Elite, `activate_free_plan!` on cancellation (triggers downgrade side effects).

## PCI / compliance

- **No** full card numbers or CVC in app DB — only Stripe IDs and plan metadata.
- **Audit:** Grep for `card_`, PAN patterns in migrations — should be empty.

## Failure modes

| Event | Behavior |
|-------|----------|
| Invalid webhook signature | Reject; no DB mutation |
| Duplicate webhook delivery | Idempotent updates on Stripe subscription id |
| User cancels in Stripe | Webhook → free plan + downgrade effects |

## Spec pointers

- `spec/requests/billing_spec.rb`, `spec/requests/stripe/webhooks_spec.rb`, services under `spec/services/billing/`.
- `spec/services/subscription_cancellation_service_spec.rb` — **`SubscriptionCancellationService`**: no sub; **local** cancel (no Stripe id); Stripe **immediate** (no `first_paid_invoice_at`); **period_end** (paid, outside refund window); **refund_and_cancel** (inside `REFUND_POLICY_WINDOW`); **StripeError** failure; **`resume!`**.
- `spec/requests/billing_spec.rb` — **`GET /billing?session_id=`** (Stripe return): paid session + metadata → **`dashboard_path`** + **`flash[:notice]`** = **`I18n.t("controllers.billing.checkout_success")`** (**mega #121**). **`GET /billing`** (active subscription): **`support_center_url`** in contact link (default + custom **`SiteSetting`**, desktop + **`:mobile`**) — **changelog 275**. **`POST /billing/cancel_subscription`** / **`resume_subscription`**: **`require_stripe_subscription!`** (HTML redirect + JSON 422 without Stripe id); success paths delegate to **`SubscriptionCancellationService`** (period-end cancel + resume; Stripe stubbed). **`POST /billing/change_plan`** / **`GET /billing/preview_plan_change`**: **`PricingPlan.active.find_by`** — missing or **inactive** **`plan_id`** → **`controllers.billing.plan_not_found`** (JSON **422** / **404**; **`change_plan`** / **`preview_plan_change`** **HTML** → **`billing_path`** + alert); no Stripe mutation. **`POST /billing/create_checkout_session` (JSON)**: missing **`price_id`** → **400** **`controllers.billing.checkout_price_id_required`**; non-trial user with **`stripe_subscription_id`** → **400** **`checkout_active_subscription_use_portal`**; **`Stripe::StripeError`** → **422** **`checkout_payment_setup_failed`**; other **`StandardError`** → **500** **`checkout_failed`**. **`POST /billing/portal` (JSON)**: **`portal`** returns **`url`** or **500** **`portal_session_create_failed`** / **`portal_customer_init_failed`** (**mega #120**).

**Related:** [billing_trial_policy.md](../systems/billing_trial_policy.md), [stripe_webhooks.md](../systems/stripe_webhooks.md) (**mega #126** HTTP contract + processor), [pricing_plans.md](../systems/pricing_plans.md) (**mega #222**), [plan_entitlements.md](../systems/plan_entitlements.md), [subscriptions_user.md](../systems/subscriptions_user.md), [free_downgrade_alliance.md](../systems/free_downgrade_alliance.md).
