# Pricing plans (catalog + Stripe price IDs)

**Last updated:** 2026-04-06 (**mega #222**, **Lane C**; **`pricing_spec`** **`GET /pricing/upgrade`** **`support_center_url`** — **changelog 274**; **`billing_spec`** **`GET /billing`** — **275**; **#224** = **Lane B** **`pricing_plan_features`** GET Turbo Frame)

## Model

**Path:** `guildsync/app/models/pricing_plan.rb`

| Area | Notes |
|------|--------|
| **Associations** | **`has_many :subscriptions`** (`restrict_with_error`). |
| **Scopes** | **`active`**, **`ordered`** (`display_order`, `created_at`), **`popular`**, **`paid_tiers`** (excludes name **Free**, case-insensitive). |
| **Identity** | **`free_tier?`** — name case-insensitive **"free"**; **`free?`** — nil/zero **`price`**. |
| **Stripe resolution** | **`effective_stripe_price_id`** / **`effective_stripe_price_id_annual`** — DB column first; else **`ENV["STRIPE_<NAME>_PRICE_ID"]`** (name uppercased, spaces → `_`). **`price_placeholder`** in DB treated as nil. |
| **Lookup** | **`find_by_stripe_price`**, **`find_by_effective_stripe_price`** (DB + scan active for ENV-backed match). |
| **Plan changes** | **`price_id_for_interval`** — month vs year price id for **`SubscriptionPlanChangeService`** / previews. |
| **Display** | **`effective_price_display_annual`** — DB **`price_display_annual`**, else computed **10%** off 12× monthly, else monthly **`price_display`**. |

## Bootstrap / sync

**Path:** `guildsync/lib/pricing_plan_initializer.rb`

- **`ensure_plans_exist!`** — run after migrations exist; **`find_or_create_by!(name)`** for **Free**, **Basic**, **Upgraded**, **Elite** (`REQUIRED_PLANS`).
- **On create:** full card/marketing attrs + **`PricingPlanCardDefaults::FEATURES_BY_PLAN_NAME`**.
- **On existing row:** **`SYNC_ATTRIBUTES`** only (`max_guilds`, `max_members_per_guild`, `max_polls`, `max_loot_rolls`, `max_events`, `can_create_alliance`) plus **`stripe_attrs_from_env`** per tier (**`STRIPE_BASIC_PRICE_ID`**, **`STRIPE_STANDARD_PRICE_ID`** fallback for Basic, annual + optional display envs).
- **Unknown plan names** → **`update_all(active: false)`** (soft-disable stray rows).
- **`migrate_standard_to_basic_if_present!`** — one-time rename **Standard → Basic** with template merge.

## Admin UI

**`Admin::PricingPlanFeaturesController`** — **`GET …/pricing-plan-features`**: **`Turbo-Frame: admin_pricing_plan_features_main`** → **`pricing_plan_features_edit_frame`** (**`layout: false`**); **`_pricing_plan_features_main`** (**flash** + **form wrap**); page title + subtitle + back outside the frame (**`data-turbo-frame="_top"`** on back + form cancel). Turbo Streams **`pricing_plan_features_refresh`** on **`PATCH`** success; validation problems → **`303`** + flash (**mega #176**). Frame GET — **mega #224**. The form includes **per-plan `feature_entitlements` checkboxes** (saved to **`pricing_plans.feature_entitlements`**) so in-app gates match admin intent alongside marketing bullet lines. See `spec/requests/admin/pricing_plan_features_spec.rb`.

## Related maps & specs

| Map / spec | Role |
|------------|------|
| [plan_entitlements.md](plan_entitlements.md) | Feature flags per tier (**`plan_entitlements.yml`**) — orthogonal to **`max_*`** limits on **`PricingPlan`**. |
| [billing_stripe_flow.md](../overall/billing_stripe_flow.md) (**#217**) | Checkout, plan change, webhooks. |
| [billing_trial_policy.md](billing_trial_policy.md) | Basic-only Stripe trials. |
| `spec/requests/billing_spec.rb` | **`change_plan`**, **`preview_plan_change`**, checkout JSON; **`GET /billing`** (**active subscription**) — **`support_center_url`** in contact link (default + custom, desktop + **`:mobile`**) — **changelog 275**. |
| `spec/requests/pricing_spec.rb` | Public **`GET /pricing`**, signed-in **`GET /pricing/upgrade`** ( **`support_center_url`** in contact copy — **changelog 274**), **`select_plan`**. |
| `spec/requests/plan_entitlements_matrix_spec.rb` | Tier gates vs **`plan_entitlements.yml`**. |
| `spec/models/pricing_plan_spec.rb` | Model behavior (scopes, **`effective_*`**, **`find_by_effective_stripe_price`**). |
| `spec/lib/pricing_plan_initializer_spec.rb` | **`ensure_plans_exist!`**, Standard→Basic migration. |
| `spec/factories/pricing_plans.rb` | Factory for **`PricingPlan`**. **Seed-plan names** (Free/Basic/Upgraded/Elite) use `find_or_initialize_by` in `to_create` to avoid uniqueness violations against seeded rows; the factory instance is marked persisted (`@new_record=false`) so subsequent `.update` calls work as `UPDATE` not `INSERT`; all attributes applied unconditionally so `stripe_price_id: nil` overrides work; transactional rollback restores the seeded values after each example. |

**Proration hint:** **`SubscriptionPlanChangeService.proration_behavior_between`** uses **`display_order`** (upgrade vs downgrade) — keep plan ordering aligned with product intent when adding tiers.
