# Plan entitlements

**Last updated:** 2026-04-08 (IRRDF — `pricing_plans.feature_entitlements` jsonb merges over YAML; admin Plan card editor saves per-plan toggles; admin-assigned trials use the same resolver)

## Source of truth

| Artifact | Path |
|----------|------|
| Matrix YAML | `guildsync/config/plan_entitlements.yml` (defaults) |
| Per-plan overrides | `pricing_plans.feature_entitlements` (jsonb; merged over YAML row for `current_plan.name.downcase`) |
| Resolver | `guildsync/app/services/plan_entitlement_service.rb` (`entitlement_row_for`, `allowed?`) |
| User API | `User#plan_allows?(feature)` — delegates to `PlanEntitlementService.allowed?` |

Plan tier is derived from `user.current_plan.name` (case-insensitive row key in YAML). Stored **`feature_entitlements`** on that `PricingPlan` row override individual flags (sparse hashes merge: missing keys still come from YAML). **`:beta_features`** also returns true when `users.beta_features_enabled` is set (admin or Elite webhook).

## Feature keys (current)

`alliance_hub`, `discord_role_sync`, `ai_gear_scanner`, `guild_documents`, `file_storage`, `activity_feed`, `warnings`, `message_center`, `member_leaderboard`, `polls`, `events`, `loot_rolls`, `settings`, `beta_features`.

## Enforcement surfaces

1. **Controllers** — `before_action` + redirect to `upgrade_pricing_path` with `plan_entitlements.upgrade_required` where product requires hard gate:
   - `MessageCenterController`, `ActivityFeedController`, `GuildWarningsController`
   - `GuildDocumentsController` (`require_guild_documents_plan!`, except `share`)
   - `StorageController` (`:file_storage`)
   - `GuildsController#members_gear` (`:ai_gear_scanner`)
2. **Views** — `plan_allows?(:symbol)` in `shared/_sidebar` (desktop + mobile) for message center, documents, gear, activity, warnings; alliance “create” gated with `:alliance_hub`.
3. **Helpers** — `ApplicationController#plan_allows?` exposed as `helper_method`; `ApplicationHelper#show_alliances_top_nav?` combines alliance tie + plan.

## Relationship to `feature_permissions.yml`

- Older matrix may still exist for legacy gates — when consolidating, prefer **one** authoritative config; document in ADR if both must coexist temporarily.

## Failure modes

| Issue | Symptom | Mitigation |
|-------|---------|------------|
| New plan name in DB but missing YAML row | `plan_allows?` false unless **`feature_entitlements`** sets flags | Add YAML row and/or set **`feature_entitlements`** in admin Plan card editor |
| Feature only in view | User crafts URL → access | Add controller guard |
| Trial user on Basic | Entitlements follow **plan name**, not “trial” label | Ensure `current_plan` is Basic during trial |

## Spec pointers

- `spec/requests/plan_entitlements_matrix_spec.rb` — Free vs Basic vs Upgraded vs **Elite** owner hitting activity feed, message center, warnings, documents, storage, **members gear** (`:ai_gear_scanner`); **Elite** row matches **Upgraded** (**200** on all listed routes).
- `spec/services/plan_entitlement_service_spec.rb` — `PlanEntitlementService.allowed?` vs `plan_entitlements.yml` (including `beta_features` and unknown plan names).
- `spec/requests/guild_documents_spec.rb` — document flows subscribe the acting users to **Upgraded** where routes require `guild_documents`.
- `spec/requests/activity_feed_spec.rb` — guild member examples subscribe to **Basic** so `ActivityFeedController` plan checks match production (`activity_feed` is off on Free).
- Index of all gate-related specs: [overall/request_specs_and_gates.md](../overall/request_specs_and_gates.md).

**Related:** [pricing_plans.md](pricing_plans.md) (**mega #222** — plan **names** / catalog), [subscriptions_user.md](subscriptions_user.md) (**`User#plan_allows?`**), [billing_trial_policy.md](billing_trial_policy.md), [billing_stripe_flow.md](../overall/billing_stripe_flow.md) (**mega #217**), [stripe_webhooks.md](stripe_webhooks.md) (**mega #126**), [sidebar_navigation.md](sidebar_navigation.md) (**mega #219**), [authorization.md](../overall/authorization.md) (**mega #211**).
