# GuildSync — production logging reference

## Where to run these commands

| Environment | What to use |
|-------------|-------------|
| **Production VM (SSH)** | File paths below (`/var/www/guildsync/guildsync/log`, `journalctl`). **Always either set `LOG_DIR` (see below) or use the full path** — if `LOG_DIR` is empty, `"$LOG_DIR/production.log"` becomes `/production.log` and `tail` fails. |
| **Your Mac (local repo)** | **`LOG_DIR` is not set** unless you export it yourself. Commands like `tail -f "$LOG_DIR/sidekiq_logs.txt"` become `tail -f "/sidekiq_logs.txt"` and **fail** with *No such file or directory*. |
| **Mac → live systemd logs** | Use **`bash deploy/live_logs.sh`** from the repo (streams `journalctl` over SSH). |

**Safe default path on the production server** (when `GUILDSYNC_LOG_DIR` is unset or matches typical deploy):

```text
/var/www/guildsync/guildsync/log
```

---

## Resolve `LOG_DIR` on the server (optional)

All app-controlled logs use **`ENV["GUILDSYNC_LOG_DIR"]`** when set in `.env`; otherwise production uses **`Rails.root/log`** (`…/guildsync/log`).

```bash
# SSH'd into the server — see what is configured:
grep -E '^GUILDSYNC_LOG_DIR=' /var/www/guildsync/guildsync/.env || echo "(unset — use …/guildsync/log)"
```

**One line that works in most shells** (set then run your `tail`/`grep`):

```bash
LOG_DIR="$(grep -E '^GUILDSYNC_LOG_DIR=' /var/www/guildsync/guildsync/.env 2>/dev/null | cut -d= -f2- | tr -d '\r')"
LOG_DIR="${LOG_DIR:-/var/www/guildsync/guildsync/log}"
echo "Using LOG_DIR=$LOG_DIR"
```

**If you skipped the above:** export a default for the rest of your SSH session:

```bash
export LOG_DIR="/var/www/guildsync/guildsync/log"
```

**Typical mistake:** `tail: cannot open '/production.log'` means `$LOG_DIR` was **unset** in that shell — run the resolver block or `export LOG_DIR=…` above, or use the **literal-path** commands in the next section.

### Literal path (no variables) — same server, copy-paste safe

Use these when you just opened SSH and do not want to manage `LOG_DIR` (adjust the root if your deploy path differs):

```text
/var/www/guildsync/guildsync/log/production.log
/var/www/guildsync/guildsync/log/puma_logs.txt
/var/www/guildsync/guildsync/log/sidekiq_logs.txt
```

**Confirmation / 500 tail (live):**

```bash
tail -f /var/www/guildsync/guildsync/log/production.log | grep -iE --line-buffered '/users/confirmation|ConfirmationsController|500|FATAL|Error \('
```

**Confirmation / 500 — last lines (non-follow):**

```bash
grep -F '/users/confirmation' /var/www/guildsync/guildsync/log/production.log | tail -50
grep -iE 'confirmationscontroller|confirmation_token|confirm_by_token|completed 500|FATAL|NoMethodError|ArgumentError' \
  /var/www/guildsync/guildsync/log/production.log | tail -80
```

**Mail/SMTP tail (live) — literal path:**

```bash
tail -f /var/www/guildsync/guildsync/log/production.log | grep -iE --line-buffered 'mail|smtp|actionmailer|MailDelivery|error|warn|ECONNREFUSED'
```

Code references: `guildsync/lib/guildsync_loggers.rb`, `guildsync/config/initializers/logging.rb`.

---

## Quick: mail / SMTP / Sidekiq (copy-paste safe)

These use a **literal path** so you never depend on an empty `$LOG_DIR`.

**Last ~80 matching lines** (`production.log` usually has `MailDeliveryJob`; `sidekiq_logs.txt` may be quieter depending on setup):

```bash
grep -iE 'mail|smtp|actionmailer|MailDelivery|deliver|ECONNREFUSED|localhost.?25|verify_profile|SignupMailer|dead|fail' \
  /var/www/guildsync/guildsync/log/sidekiq_logs.txt \
  /var/www/guildsync/guildsync/log/production.log 2>/dev/null | tail -80
```

**Follow `production.log` live** (Ctrl+C to stop):

```bash
tail -f /var/www/guildsync/guildsync/log/production.log | grep -iE --line-buffered 'mail|smtp|actionmailer|MailDelivery|error|warn|ECONNREFUSED'
```

**Follow `sidekiq_logs.txt` live:**

```bash
tail -f /var/www/guildsync/guildsync/log/sidekiq_logs.txt | grep -iE --line-buffered 'mail|smtp|actionmailer|MailDelivery|error|warn|ECONNREFUSED|WARN'
```

---

## From your Mac without opening SSH manually

**Remote grep** (adjust host and path if your tree differs):

```bash
ssh deploy@guild-sync.net 'grep -iE "mail|smtp|MailDelivery|ECONNREFUSED" /var/www/guildsync/guildsync/log/production.log | tail -40'
```

**Live systemd/journal** (from repo root):

```bash
bash deploy/live_logs.sh
bash deploy/live_logs.sh --sidekiq
bash deploy/live_logs.sh --grep "MailDelivery"
bash deploy/live_logs.sh --errors
```

Override: `DEPLOY_SERVER=deploy@your.host bash deploy/live_logs.sh`

**Remote live tail** (runs on server; `-t` allocates TTY for clean Ctrl+C; uses **literal** log path):

```bash
ssh -t deploy@guild-sync.net 'tail -f /var/www/guildsync/guildsync/log/production.log | grep -iE --line-buffered "/users/confirmation|ConfirmationsController|500|FATAL"'
```

```bash
ssh -t deploy@guild-sync.net 'tail -f /var/www/guildsync/guildsync/log/production.log | grep -iE --line-buffered "mail|smtp|actionmailer|MailDelivery|error|warn|ECONNREFUSED"'
```

**Remote one-shot grep** (full path, no `LOG_DIR` on either side):

```bash
ssh deploy@guild-sync.net 'grep -F "/users/confirmation" /var/www/guildsync/guildsync/log/production.log | tail -40'
```

```bash
ssh deploy@guild-sync.net 'grep -iE "completed 500|FATAL|confirm_by_token|ConfirmationsController" /var/www/guildsync/guildsync/log/production.log | tail -60'
```

---

## Investigating `GET /users/confirmation` (wrong URL) and similar HTTP 500s

**Symptom:** Browser shows **HTTP ERROR 500** on `https://guild-sync.net/users/confirmation` with **no** `confirmation_token` query param. The resend form lives at **`/users/confirmation/new`**; the bare **`/users/confirmation`** route is Devise **`confirmations#show`** and expects `?confirmation_token=…` from the email link. If the app does not guard a blank token, logs may show an exception during `confirm_by_token`.

### Safe checks from your machine (no body, status codes only)

Print **only** the HTTP status code so you do not paste HTML/error pages into tickets:

```bash
curl -sS -o /dev/null -w "GET /users/confirmation     -> %{http_code}\n"  "https://guild-sync.net/users/confirmation"
curl -sS -o /dev/null -w "GET /users/confirmation/new -> %{http_code}\n"  "https://guild-sync.net/users/confirmation/new"
```

Optional: confirm the **email link** shape returns **302** (or 200 after fix) instead of 500 (use a **short test token** if you have one; do not paste real full tokens into chat logs):

```bash
curl -sS -o /dev/null -w "%{http_code}\n"  "https://guild-sync.net/users/confirmation?confirmation_token=INVALID"
```

### On the production VM — resolve `LOG_DIR` then search (low-noise)

```bash
LOG_DIR="$(grep -E '^GUILDSYNC_LOG_DIR=' /var/www/guildsync/guildsync/.env 2>/dev/null | cut -d= -f2- | tr -d '\r')"
LOG_DIR="${LOG_DIR:-/var/www/guildsync/guildsync/log}"
```

**Requests touching the confirmation path** (last 50 hits):

```bash
grep -F '/users/confirmation' "$LOG_DIR/production.log" | tail -50
```

**Literal path:**

```bash
grep -F '/users/confirmation' /var/www/guildsync/guildsync/log/production.log | tail -50
```

**Likely stack traces / fatal errors** near confirmation or any 500 (adjust `tail` as needed):

```bash
grep -iE 'confirmationscontroller|confirmation_token|confirm_by_token|completed 500| Processing .*500|ActionController::RoutingError|FATAL|NoMethodError|ArgumentError|undefined method' \
  "$LOG_DIR/production.log" | tail -80
```

**Literal path:**

```bash
grep -iE 'confirmationscontroller|confirmation_token|confirm_by_token|completed 500| Processing .*500|ActionController::RoutingError|FATAL|NoMethodError|ArgumentError|undefined method' \
  /var/www/guildsync/guildsync/log/production.log | tail -80
```

**Puma’s file** (some crashes or low-level errors appear here):

```bash
grep -iE 'error|exception|500|confirmation' "$LOG_DIR/puma_logs.txt" 2>/dev/null | tail -50
```

**Literal path:**

```bash
grep -iE 'error|exception|500|confirmation' /var/www/guildsync/guildsync/log/puma_logs.txt 2>/dev/null | tail -50
```

### Live follow (cautious — stop with Ctrl+C)

If **`$LOG_DIR` is empty**, these expand to `/production.log` and break. Either **set `LOG_DIR` first** (resolver block above) or use the **literal-path** variants in the same subsection.

Watch **production** for confirmation URLs and errors (narrow filter):

```bash
tail -f "$LOG_DIR/production.log" | grep -iE --line-buffered '/users/confirmation|ConfirmationsController|500|FATAL|Error \('
```

**Same command, literal path** (no variables):

```bash
tail -f /var/www/guildsync/guildsync/log/production.log | grep -iE --line-buffered '/users/confirmation|ConfirmationsController|500|FATAL|Error \('
```

Broader **“catch 500s and fatals”** (noisier):

```bash
tail -f "$LOG_DIR/production.log" | grep -iE --line-buffered 'completed 500|500 Internal|FATAL|Unhandled|NoMethodError|ArgumentError|Error:'
```

**Literal path:**

```bash
tail -f /var/www/guildsync/guildsync/log/production.log | grep -iE --line-buffered 'completed 500|500 Internal|FATAL|Unhandled|NoMethodError|ArgumentError|Error:'
```

### One-shot over SSH (no interactive tail)

Same **literal-path** greps as in **From your Mac without opening SSH manually** (duplicate for readers who jump here). Replace host if needed:

```bash
ssh deploy@guild-sync.net 'grep -F "/users/confirmation" /var/www/guildsync/guildsync/log/production.log | tail -40'
```

```bash
ssh deploy@guild-sync.net 'grep -iE "completed 500|FATAL|confirm_by_token|ConfirmationsController" /var/www/guildsync/guildsync/log/production.log | tail -60'
```

### Correlate with systemd (boot / worker / OOM — not request-level)

Use when the app restarts or Puma dies around the time of the 500:

```bash
sudo journalctl -u guildsync -u guildsync-sidekiq --since "1 hour ago" --no-pager -o short-iso | tail -100
```

### Reporting

When opening an incident, include: **exact URL** (with/without query string), **time (UTC)**, and a **redacted** `production.log` line block (request start + completed line + any following exception). Strip cookies, tokens, and emails if present.

---

## Log files (under `LOG_DIR`)

| File | Contents |
|------|-----------|
| **`production.log`** | Main Rails log (Puma + much Sidekiq `ActiveJob` output in practice). |
| **`sidekiq_logs.txt`** | Dedicated Sidekiq file logger. |
| **`puma_logs.txt`** | Puma logger. |
| **`discord.log`** | Discord gateway (very chatty). |
| **`discord_failures.txt`**, **`job_monitoring.txt`**, **`startup_checks.txt`**, … | See `GuildsyncLoggers::DEDICATED_LOG_FILES` in `guildsync/lib/guildsync_loggers.rb`. |

Rotation: rolling/daily for main appenders; dedicated `*.txt` subject to `LogRotationJob` (see `guildsync/app/jobs/log_rotation_job.rb`).

---

## systemd journal (`journalctl`)

Useful for **boot errors**, crashes, and anything on stdout/stderr. Not a replacement for `production.log` for app-level mail lines.

```bash
sudo journalctl -u guildsync -u guildsync-sidekiq -f --no-pager -o short-iso
sudo journalctl -u guildsync-sidekiq -n 200 -f --no-pager -o short-iso
sudo journalctl -u guildsync -u guildsync-sidekiq -p warning -n 200 -f --no-pager -o short-iso
```

---

## ENV related to logging

| Variable | Effect |
|----------|--------|
| **`GUILDSYNC_LOG_DIR`** | Root directory for all file logs above. |
| **`RAILS_LOG_LEVEL`** | Verbosity in production (default `info`). `guildsync/config/environments/production.rb`. |

---

## Service status

```bash
sudo systemctl status guildsync guildsync-sidekiq --no-pager
```

---

## One-shot Rails check (SMTP `config` vs `base` — as `deploy`)

Run **on the server**; loads `.env` like systemd:

```bash
sudo -u deploy -H bash -lc 'cd /var/www/guildsync/guildsync && set -a && source .env && set +a && export RAILS_ENV=production && bundle exec rails runner "puts %q(config=) + Rails.application.config.action_mailer.smtp_settings[:address].to_s; puts %q(base=) + ActionMailer::Base.smtp_settings[:address].to_s"'
```

Expect **`smtp.resend.com`** for both lines after the `ActionMailer::Base.smtp_settings` sync fix is deployed.

**Do not** paste Ruby like `ActionMailer::Base.smtp_settings = …` at a bash `#` prompt; use `rails runner` / `rails c` or change app code.

---

## Reading logs: success vs failure for mail jobs

- **Failure:** Sidekiq WARN / `ECONNREFUSED`, `dead` job lines, or job ends without deliver.
- **Success:** `Performed ActionMailer::MailDeliveryJob ... in …ms` (typically ~1–2s when talking to a real SMTP host). Confirm delivery in **Resend** and the inbox.

---

## Security

- Redact secrets when sharing log snippets.
- Random **404/scan** lines like `GET /smtp/secrets.env` are internet noise; ensure no such files exist in `public/` and secrets stay in `.env` (not web-accessible).
