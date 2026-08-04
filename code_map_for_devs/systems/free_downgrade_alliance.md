# Free plan downgrade side effects

**Last updated:** 2026-04-06

**Service:** `guildsync/app/services/free_plan_downgrade_side_effects.rb`  
**Triggers:** `User#activate_free_plan!`, `User#convert_expired_trial_to_free!`, `User#downgrade_to_free_during_trial!`, `StripeWebhookProcessor#handle_subscription_deleted`.

**Behavior:** Removes owner's guilds from active alliances (marks `AllianceGuild` left). If an alliance `leader_guild` is removed, promotes the next active member guild by oldest `alliance_guilds.created_at` and sets `leader_user` to that guild's owner. Snapshots alliance ids in `users.alliance_downgrade_snapshot` for optional restore UX.

**Tests:** `spec/services/free_plan_downgrade_side_effects_spec.rb` — `nil` user; no alliance membership (empty snapshot); **leader + successor** (left status, new `leader_guild` / `leader_user`, `AllianceMember` removed, snapshot); **non-leader** owned guild (only that guild leaves; leadership unchanged).

## Related

- [billing_stripe_flow.md](../overall/billing_stripe_flow.md) (**mega #217**) — cancel / free paths that call into **`User`** billing methods.
- [stripe_webhooks.md](stripe_webhooks.md) (**mega #126**) — subscription deleted handling.
- [subscriptions_user.md](subscriptions_user.md) — **`activate_free_plan!`**, **`convert_expired_trial_to_free!`**, **`downgrade_to_free_during_trial!`**.
- [alliances.md](alliances.md) — alliance model; **Lane D** for deeper alliance UI/bot slices.
- [plan_entitlements.md](plan_entitlements.md) — Free tier feature matrix vs paid.
- [data_model_core.md](../overall/data_model_core.md) (**mega #209**) — **`AllianceGuild`**, **`AllianceMember`** relationships.
- [request_specs_and_gates.md](../overall/request_specs_and_gates.md) — service spec row / gate bundle.
