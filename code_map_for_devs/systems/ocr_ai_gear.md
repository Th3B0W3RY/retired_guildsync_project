# AI Stat Scanner (OCR)

**Last updated:** 2026-05-31 — Content-only OCR, upload JSON auth contract (**`StatScanner::UniversalStatParser`**), **`member_stats`** page, members gear list without per-game filter; internal plan key remains **`:ai_gear_scanner`** (see **`plan_entitlements.yml`**).

**Last activity timestamps:** **`GearSnapshot#last_activity_at`** is the later of **`created_at`** (scan) and **`updated_at`** (e.g. officer edits via **`GearSnapshots::UpdateExtractedData`**). **`GuildsController#members_gear`** uses it for each row’s **`last_updated`**; **`member_stats`** views use it for the heading line. **`GearController#upload`** / **`#show`** JSON include **`last_activity_at`** (and **`created_at`**). **`after_commit :touch_uploader_guild_membership, on: :create`** **`touch`**es the uploader’s **`GuildMember`** on every successful new scan (web + Discord). Discord **`/gear my`** uses **`last_activity_at`** for “Last updated”.

**Limits:** `Ocr::UsageTracker::PLAN_LIMITS` — free/basic/trial: 3/mo; upgraded: 4900; elite: 9900; buffer 0 for hard stop at limit.  
**Entry:** `GearOcrService` → `Ocr::UsageTracker.check` before external OCR.  
**Stat extraction is content-based and game-agnostic (no screen-position geometry):** Azure **`lib/scripts/azure_ocr.js`** sorts lines into reading order (**`sortVisualLines`** using per-line bounding boxes) and keeps text from **anywhere** on screen — left, center, or right panels — so left-panel games (e.g. **ArcheAge** "Character Info" on the left) work the same as right-panel games. The only position-independent cut in the script is dropping **bracketed chat** (`[Channel] Name: ...`) via **`OCR_FILTER_BRACKET_LINES`** (default on). There is **no** region/x-ratio geometry filter and **no** `STAT_SCAN_OCR_*` env tuning — those were removed because screen layout differs per game and cannot generalize. What counts as a stat is decided downstream by **content** rules in **`StatScanner::UniversalStatParser`** (and **`StatScanner::OcrTextPrefilter`** for bracketed chat in plain-text engines). **`GearOcrService`** stores the full **`raw_text`** on the response; **`data`** is parsed from it.

**Empty-parse policy (web upload):** when OCR returns text but **`UniversalStatParser`** extracts **no** label/value pairs, **`GearController#upload`** still **saves** the **`GearSnapshot`** (screenshot kept for retry / officer review, matching Discord) but does **not** report a clean success: it sets the snapshot **`validation_warning`** to **`gear.api.stats_not_extracted`** (unless an embedding warning already applies) and returns **`stats_extracted: false`** in the JSON. The members-gear upload JS then shows a **warning** toast and skips the green **`gear_upload_success`** redirect, so the user is told to retry instead of seeing "uploaded successfully" with an empty **View Stats**. Discord (**`DiscordGearService`**) already messages **"No stats extracted from image"** for the same case.

**Parsing:** `GearOcrService` uses **`StatScanner::UniversalStatParser`** on filtered OCR text: `:`, tab, 2+ spaces, em dash; **same-line** `Label 123` / `6.9 m/s (127.1%)` / `5790 (1150 + 4640)`; **multiple pairs per line** when OCR merges rows; **column OCR** where the **value is on the next line** only (standalone numeric line pairs with the previous label). **Filtered noise:** minimap **coordinates**; **single-digit-only values**; **keyboard / action-bar** labels — `(W)Dn`-style, parenthetical-only hotkey text, **`Shift`/`Ctrl`/`Alt`/`Cmd`+key** (spaced or `+`), bare **`F1`–`F12`**, **single-letter** slots, **Tab/Esc/Enter/Home/End/PgUp**-style key names, **mouse (`MB`/`Mouse`)** and **numpad** labels, **`Q + E`** chords, **`Key 7`** OCR; **chat / system-message sentences** (`UniversalStatParser#chat_or_sentence_pair?`) — label longer than **`MAX_STAT_LABEL_WORDS`** (6), word-only value longer than **`MAX_STAT_VALUE_WORDS`** (6), or a value ending in `!`/`?` — so non-bracketed chat that survives the bracket cut does not become a junk stat, while short text stats (`Faction: Haranya Alliance`, `Title: ...`) are kept. **`GearSnapshot#data`** is a flat string→string hash. Extraction still depends on OCR text quality; game-specific **`Game#parse_gear_data`** handlers are **not** used on upload. Re-upload to refresh **`data`**.

**OCR billing subject:** `Ocr::BillingSubject.for_gear_upload(actor:, guild:)` — if `guild.owner` has `plan_allows?(:ai_gear_scanner)` (via `PlanEntitlementService` / `current_plan`) and the actor is an **active** `guild_member`, `Ocr::UsageTracker.check` / `increment_after_success!` use the **owner’s** user row (shared guild pool). Otherwise the **actor’s** row is used. `GearController#upload` and `DiscordGearService` pass `guild:` into `GearOcrService.process_image`.

**Who clicked upload (initiator vs billed account):** `OcrRequest` has optional **`initiated_by_id`** → `users`. `Ocr::UsageTracker.increment_after_success!` / `check_and_increment!` accept **`initiated_by:`**; when the billed `user` and initiator differ, the row stores **`initiated_by_id`** (same account → `nil`). `GearOcrService` passes the uploader after success. Rapid-request abuse detection (`OcrRequest#check_abuse_patterns`) counts by **`COALESCE(initiated_by_id, user_id)`** so spam flags the person triggering uploads, not only the billed owner. **Guild activity feed:** `GearStatScanActivityLog.log_successful_upload` → `GuildActivityLogger` **`gear_uploaded`** — copy from **`gear.activity.uploaded`** or **`gear.activity.uploaded_shared_guild_plan`** when OCR is billed to the guild leader; metadata may include **`ocr_billed_to_name`**. Admin user OCR show lists an **Initiator** column (**`admin.ocr_requests.show.initiated_by`**).

**Web upload:** `GearController#upload` calls `GearOcrService.process_image(..., user: current_user, request: request, guild: @guild)` so quota checks and optional **IP abuse** limits in `Ocr::UsageTracker.check` see the Rack request. **`GearController`** uses **`prepend_before_action :force_json_format`** on upload so session/MFA filters return **JSON** (401/403) instead of HTML redirects; the members-gear **`fetch`** sends **`Accept: application/json`** and **`credentials: same-origin`**. Unsigned → **401** (`api.v1.authentication_required`); MFA not satisfied → **403** (`gear.api.mfa_required`). **`GearController#set_guild`** resolves **`@guild`** like **`GuildsController`**; users without access get **404** JSON **`error`** = **`controllers.guilds.access_denied`**. **`#show`** resolves the target with **`@guild.members.find_by(id: params[:user_id])`**; missing → same **404** **`access_denied`**. Validation, OCR failure, and related errors use **`gear.api.*`** in **`config/locales/{locale}/{locale}.yml`**. **Frontend:** Trix/ActionText load only when a **`trix-editor`** is present (not on every page) — see **`app/javascript/application.js`**.

**Observability:** Unexpected OCR pipeline exceptions and **`GearController#upload`** outer rescues call **`ErrorLogger.capture`** (Admin → **Error Tracker** at **`/admin/errors`**). Embedding generation failures and Active Storage attach failures during upload are captured at **medium** severity. **Expected** user errors (wrong MIME type, file too large, quota exceeded, empty OCR text) return **422** JSON and **do not** create **`ErrorLog`** rows.

**Discord upload:** `DiscordGearService#handle_upload_command` passes **`Ocr::ChannelRequest.for_discord_gear_upload`** as **`request:`** and **`guild:`** for owner billing.

**User OCR tier:** `User#ocr_plan` uses `ocr_billing_plan` when set; otherwise it maps **`current_plan.name`** to `Ocr::UsageTracker::PLAN_LIMITS` so limits stay aligned with Stripe-backed plans when the column lags. Image download failures, embedding failures, and top-level channel-message handler exceptions are **`ErrorLogger.capture`**’d (medium/high as appropriate).

**Admin:** `Admin::OcrRequestsController` — AI Scan Request menu. Coordinate **Lane B** before parallel edits to admin OCR index/bulk Turbo.

## Members stat scanner page (`GuildsController#members_gear`)

| Item | Detail |
|------|--------|
| Route | **`GET /guilds/:id/members/gear`** — **`guild_members_gear_path(@guild)`** |
| Guild context | Standard **`GuildsController`** **`set_guild`** / membership chain applies before action body. |
| Plan gate | **`current_user.plan_allows?(:ai_gear_scanner)`** — if false → **`redirect_to upgrade_pricing_path`** + **`plan_entitlements.upgrade_required`**. |

**Assigns (core):**

- **`@my_pending_gear_request`** — **`GearUploadRequest.pending_for_user(@guild, current_user).includes(:requester).first`**. When present, desktop + mobile **`guilds/members_gear`** show the pending-request officer banner.
- **`@members_with_gear`** — per-member **`GearSnapshot`** status (**`missing` / `outdated` / `up_to_date`**) using the **latest snapshot for that member in the guild (any game)**; **`params[:status]`** filters when not **`all`**.
- **`@gear_stats`** — counts including **`pending_requests`** = **`GearUploadRequest.where(guild: @guild, status: :pending).count`** (computed from the **unfiltered** member list before status filter).
- **`@members_with_pending_requests`** — **`User`** records whose ids appear as **`target_user_id`** on **pending** **`GearUploadRequest`** rows for the guild.
- **`@current_user_snapshot`** — latest **`GearSnapshot`** for **`current_user`** in the guild (any game).

**Edge cases:** No games on guild → early return with empty **`@members_with_gear`** and zeroed stats; empty member list → similar minimal assigns.

## Per-member stats page (`GuildsController#member_stats`)

| Item | Detail |
|------|--------|
| Route | **`GET /guilds/:id/members/stats/:user_id`** — **`guild_member_stats_path(@guild, user_id)`** |
| Plan gate | Same **`plan_allows?(:ai_gear_scanner)`** as **`members_gear`**. |
| Assigns | **`@target_user`**, **`@snapshot`** (latest any game), **`@stat_rows`** from **`GearSnapshot#stat_rows`**. |

**i18n:** **`guilds.members_gear.*`**, **`guilds.member_stats.*`**, and **`gear.*`** keys live under locale files per **`i18n-tasks.yml`**.

**Specs:** **`spec/requests/gear_spec.rb`** — upload, **`GET …/members_gear`**, **`support_center_url`**, members gear **last activity** display; **`spec/requests/member_stats_spec.rb`** — stats page, last-updated line vs **`updated_at`**; **`spec/models/gear_snapshot_spec.rb`** — **`#last_activity_at`**, **`GuildMember`** touch on create; **`spec/services/gear_ocr_service_spec.rb`**; **`spec/services/discord_gear_service_spec.rb`**; **`spec/services/ocr/usage_tracker_spec.rb`** (**`initiated_by`**, rapid-flag on initiator); **`spec/services/gear_stat_scan_activity_log_spec.rb`**.

**Related:** **`overall/error_observability.md`** (**`ErrorLogger`**), **`systems/storage_files.md`**, **`plan_entitlements_matrix_spec`** (**`ai_gear_scanner`** gate), **`GearController`**.
