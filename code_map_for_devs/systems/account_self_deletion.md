# Account self-deletion

End-user flow to close an account from **Settings → Account** (red section), with email verification code and a client-side final confirmation before `POST` completes deletion.

## Retention policy (restore semantics)

- **Soft close (Phase A):** Immediately after confirmation, [`AccountDeletionJob`](../../guildsync/app/jobs/account_deletion_job.rb) runs [`AccountDeletion::PurgeService#call_soft`](../../guildsync/app/services/account_deletion/purge_service.rb): Stripe teardown (if configured), local subscription rows removed, signup verification rows cleared, `account_deletion_request` destroyed. **User email/username and all `UserRestoration::Registry` graph rows remain** so the account can be re-opened via admin restore during retention.
- **Hard purge (Phase B):** After **`SoftDeletable::RETENTION_PERIOD`** (6 months) from `account_closed_at`, [`AccountHardPurgeJob`](../../guildsync/app/jobs/account_hard_purge_job.rb) runs [`PurgeService#call_hard`](../../guildsync/app/services/account_deletion/purge_service.rb): destroys owned graph (FK order), tombstones `User`, sets `account_data_purged_at`.
- **Admin restore:** Within the retention window and **before** hard purge, [`AccountClosure::AdminRestore`](../../guildsync/app/services/account_closure/admin_restore.rb) clears `archived`, `account_closed_at`, `account_deletion_started_at`, and `account_closure_soft_completed_at`. **Billing/subscriptions are not recreated**; operators manage trials/plans separately. **Discord** is not auto-re-linked.

## Feature flag

- [`AccountDeletion.feature_enabled?`](../../guildsync/app/services/account_deletion.rb): **non-production** environments always treat self-deletion as enabled (for dev/staging QA). **Production:** self-service deletion is **on by default** after deploy; the feature is off in production **only** when `ACCOUNT_SELF_DELETE_ENABLED=0` (explicit opt-out / kill switch).

## Production / deploy

1. Deploy the app; **no env var is required** for the feature to be available in production.
2. To disable quickly, set **`ACCOUNT_SELF_DELETE_ENABLED=0`** on the production host and restart the app process.
3. Env contract: **`guildsync/.env.example`**.

## Routes and controller

- `POST /account/deletion/send_code` — [`AccountDeletionsController#send_code`](../../guildsync/app/controllers/account_deletions_controller.rb): eligibility check, resend cooldown, issues code via [`AccountDeletionRequest#issue_code!`](../../guildsync/app/models/account_deletion_request.rb), emails [`AccountMailer.deletion_code`](../../guildsync/app/mailers/account_mailer.rb) (`deliver_now`), audit `account_deletion_code_sent`.
- `POST /account/deletion/confirm` — `#confirm`: re-checks eligibility, [`verify_submitted_code`](../../guildsync/app/models/account_deletion_request.rb) (consumes code on success), then archives user, signs out, audit `account_deletion_confirmed`, enqueues [`AccountDeletionJob.perform_async`](../../guildsync/app/jobs/account_deletion_job.rb) (Sidekiq worker).

## UI

- View: [`app/views/settings/account.html.erb`](../../guildsync/app/views/settings/account.html.erb) (`@account_deletion_feature`).
- Stimulus: [`app/javascript/controllers/account_deletion_controller.js`](../../guildsync/app/javascript/controllers/account_deletion_controller.js) — code length gate, modal for final confirm; only **Yes** submits confirm (single `POST` preserves one-shot code consumption).

## Code / limits

- Code: 8 hex chars, TTL **`AccountDeletionRequest::CODE_TTL`** (45 minutes), max attempts **`MAX_VERIFICATION_ATTEMPTS`**, resend cooldown aligned with signup verification.
- Rack::Attack: throttle keys for `send_code` and `confirm` by IP — see [`config/initializers/rack_attack.rb`](../../guildsync/config/initializers/rack_attack.rb).

## Eligibility

- [`AccountDeletion::EligibilityChecker`](../../guildsync/app/services/account_deletion/eligibility_checker.rb) — used on `send_code` and again on `confirm`. **`:purge_in_progress`** is keyed off `account_deletion_started_at` and `account_closure_soft_completed_at` (Phase A completion).

## Admin restore

- **User admin show:** [`app/views/admin/users/_users_show_main.html.erb`](../../guildsync/app/views/admin/users/_users_show_main.html.erb) — retention copy; [`Admin::UsersController#reactivate_account`](../../guildsync/app/controllers/admin/users_controller.rb) delegates to **`AccountClosure::AdminRestore`** (flash keys under `admin.users.reactivate`).
### User helper

- [`User#account_closure_hard_purge_due_at`](../../guildsync/app/models/user.rb) — `account_closed_at` + `SoftDeletable::RETENTION_PERIOD` for display.

## Specs

- [`spec/requests/account_deletions_spec.rb`](../../guildsync/spec/requests/account_deletions_spec.rb)
- [`spec/jobs/account_deletion_job_spec.rb`](../../guildsync/spec/jobs/account_deletion_job_spec.rb), [`spec/jobs/account_hard_purge_job_spec.rb`](../../guildsync/spec/jobs/account_hard_purge_job_spec.rb)
- [`spec/services/account_deletion/purge_service_spec.rb`](../../guildsync/spec/services/account_deletion/purge_service_spec.rb)
- [`spec/services/account_closure/admin_restore_spec.rb`](../../guildsync/spec/services/account_closure/admin_restore_spec.rb)
