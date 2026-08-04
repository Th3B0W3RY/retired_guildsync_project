# Stripe webhooks

**Last updated:** 2026-04-06 (**mega #126** — endpoint **`head`**-only audit, no user-facing i18n; see **[`overall/billing_stripe_flow.md`](../overall/billing_stripe_flow.md)** **mega #217** for checkout/portal + processor context)

## Entry point

- **Route:** `POST` webhook endpoint (see `config/routes.rb` under `Stripe::WebhooksController`).
- **Controller:** `guildsync/app/controllers/stripe/webhooks_controller.rb`
  - Reads **raw** request body (required for signature verification).
  - Header: `HTTP_STRIPE_SIGNATURE` or `Stripe-Signature`.
  - Env: `STRIPE_WEBHOOK_SECRET` — if unset, events must not be trusted (controller logs error).

## Verification

```ruby
Stripe::Webhook.construct_event(payload, sig, secret)
```

Raises `Stripe::SignatureVerificationError` on bad signature → typically 400 response, **no** subscription mutation.

## Processing

- **`StripeWebhookProcessor`** — Handles `customer.subscription.*`, `invoice.*`, etc.
- **Idempotency:** `stripe_webhook_events` (or equivalent) stores event IDs to avoid double-apply.
- **Side effects:** Update/create `Subscription`, sync `User` Stripe fields, set `beta_features_enabled` on Elite, call `activate_free_plan!` on cancellation (which may run `FreePlanDowngradeSideEffects`).

## Failure modes

| Event | Risk |
|-------|------|
| Replay attack without signature check | Fraudulent premium — **prevented** by construct_event |
| Processor raises mid-transaction | Partial DB state — processor should use transactions where needed |
| Webhook secret rotated | All events fail until env updated — monitor logs |

## Spec pointers

- `spec/requests/stripe/webhooks_spec.rb` — signature verification, processor behavior.

**Related:** [overall/billing_stripe_flow.md](../overall/billing_stripe_flow.md), `systems/subscriptions_user.md`, `systems/free_downgrade_alliance.md`.
