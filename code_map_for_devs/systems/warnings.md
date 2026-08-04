# Guild warnings

**Last updated:** 2026-04-06 (**mega #180**, **Lane C**; **`guild_warnings_spec`** **`support_center_url`** on **`GET …/warnings`** + **`GET …/warnings/me`** — **changelog 285**)

**Controller:** `guildsync/app/controllers/guild_warnings_controller.rb`  
**Gates:** `plan_allows?(:warnings)` (checked before role/owner rules); `can_manage_warnings?` / owner for management UI; `my_status` skips the plan hook but requires membership. `protected_warning_target?` blocks acting on the guild owner and anyone who can manage warnings.

**Specs:** `spec/requests/guild_warnings_spec.rb` (roles, protected targets, **Basic plan** subscription in setup so plan gate matches production; **`support_center_url`** in member chrome on **`GET …/warnings`** and **`GET …/warnings/me`** — **changelog 285**). Isolation: unknown guild → `my_guilds_path`; non-member `user_id` on create → `member_not_found`. Plan matrix: `spec/requests/plan_entitlements_matrix_spec.rb`.

## Related

- [plan_entitlements.md](plan_entitlements.md) — **`:warnings`**.
- [sidebar_navigation.md](sidebar_navigation.md) (**mega #219**).
- [activity_feed.md](activity_feed.md) — plan-gated guild feature; shared matrix patterns.
- [message_center.md](message_center.md) (**mega #182**).
- [request_specs_and_gates.md](../overall/request_specs_and_gates.md).
