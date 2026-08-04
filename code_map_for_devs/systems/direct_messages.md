# Direct messages (Message Center persistence)

**Last updated:** 2026-04-06 (**mega #184**, **Lane C**; **`message_center_isolation_spec`** index **`support_center_url`** — **changelog 284**)

## Model

- **`guildsync/app/models/direct_message.rb`** — `sender` / `recipient` (`User`), optional `guild` (`Guild`). `encrypts :content`. Scopes: `between(user_a, user_b)`, `recent_first`.

## Controller behaviour

- **`MessageCenterController#conversation`** loads `DirectMessage.between(current_user, recipient).where("guild_id IS NULL OR guild_id = ?", @guild.id)` so messages stored under **another guild’s** `guild_id` do not appear in the current guild’s thread.
- **`guild_id_for_conversation`** sets `guild_id` to `@guild.id` when the recipient is a member of `@guild`; otherwise `nil` (e.g. owner-to-owner paths).

## Failure / abuse modes

- Invalid recipient → JSON **422** (`message_center.invalid_recipient`) on both **`create`** and **`conversation`**.
- Non-member or missing `can_use_message_center?` → redirect to guild with `message_center.access_denied`.
- Plan: `require_message_center_plan!` → `upgrade_pricing_path` when `!plan_allows?(:message_center)`.

## Specs

- `spec/requests/message_center_isolation_spec.rb` — isolation and persistence; index **`support_center_url`** (**changelog 284**).
- `spec/requests/plan_entitlements_matrix_spec.rb` — plan gate for message center UI.

**Related:** [message_center.md](message_center.md) (**mega #182** — controller + routes), [plan_entitlements.md](plan_entitlements.md) (**`:message_center`**), [request_specs_and_gates.md](../overall/request_specs_and_gates.md).
