# Admin guild ownership transfer

**Last updated:** 2026-04-06 (**mega #225** GET Turbo Frame, Lane B)

## Purpose

Let support move **`Guild#owner`** to another **`User`** from the admin area (linked from **`admin/users#show`** per owned guild). This is **not** a self-serve feature; it uses **`Admin::BaseController`** session auth.

## Key paths

| Piece | Path |
|-------|------|
| Controller | `guildsync/app/controllers/admin/guild_transfers_controller.rb` |
| Service | `guildsync/app/services/admin/guild_ownership_transfer_service.rb` — ownership update + optional **`SubscriptionCancellationService`** for the previous owner |
| Routes | `GET /admin/guild_transfers/new/:guild_id`, `POST /admin/guild_transfers/create` |
| Audit | `AdminAuditLog` action **`transfer_guild_ownership`** with `changes_data`: old/new owner ids, **`cancel_previous_owner_billing`**, **`billing_outcome`**, optional **`billing_mode`** / **`billing_error`** |

## Billing (optional)

- Form checkbox **`cancel_previous_owner_billing`** (hidden **`0`** + checkbox **`1`**). When checked, after the transfer **`Admin::GuildOwnershipTransferService`** runs **`SubscriptionCancellationService.call`** for the **previous** owner **only if** **`active_owned_guilds_count`** is **zero** (same rules as member self-serve billing: local cancel without Stripe id; Stripe paths otherwise). If they still own other guilds, billing is skipped and the flash explains why.
- Copy: **`admin.guild_transfers.*`** in all **10** `admin.{locale}.yml` files.

## Turbo / form submit

- **`GET …/guild_transfers/new/:guild_id`**: **`Turbo-Frame: admin_guild_transfers_new_main`** → **`guild_transfers_new_frame`** (**`layout: false`**); **`_guild_transfers_new_main`** holds the guild card + form; page **`h1`** and back link stay outside the frame; back, form **cancel**, and **`admin/users/show`** **transfer ownership** use **`data-turbo-frame="_top"`** — **mega #225**.
- **`admin/guild_transfers/new`** uses Turbo-enabled **`form_with`** (no **`local: true`**). **`POST …/create`** with **`Accept: text/vnd.turbo-stream.html`** responds with **`303 See Other`** to **`admin_user_path(new_owner)`** and the same flash notice as HTML (**mega #178**).

## Specs

- `spec/requests/admin/guild_transfers_spec.rb` — full **`GET …/new`**, **Turbo-Frame** frame-only **`GET`**, happy path, **optional billing** (calls / does not call **`SubscriptionCancellationService`**), **authentication** for **new** / **create**, Turbo **`POST …/create`** **`see_other`** redirect.
- `spec/services/admin/guild_ownership_transfer_service_spec.rb` — billing outcomes: not requested, applied (**local** and **Stripe `period_end`** stub), skipped (still owns guilds), no subscription.

**Related:** `systems/account_self_deletion.md` (admin restore of self-closed accounts), `systems/admin_dashboard.md`.
