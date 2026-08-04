# Feature requests / roadmap

**Last updated:** 2026-04-08 (public **`#index`**: signed-in **hint + release-notes callout card removed**; status **tablist** sits **directly under** search/create row; removed **`roadmap.signed_in_create_hint`**, **`roadmap.moderation_rules_notice`**, **`roadmap.release_notes_instructions_signed_out`** from all **10** locales; **`roadmap.admin.release_notes.used_roadmap`** copy updated; **`roadmap_spec`** asserts tablist **before** **`roadmap_column_list_*`** — supersedes **changelog 265** / **276** index-only behavior; prior: admin Kanban **`#index`** + **`#edit`** Turbo Frames — **mega #230** / **#231**; **BLOCKLIST** — **mega #195**; **`release_notes_spec`** guest title — **260**; guest **`:mobile`** — **266**; signed-in **`GET /roadmap/:id`** **`support_center_url`** — **301**)

**Purpose:** Public roadmap board, voting, and moderated submissions tied to admin content review.

## Routes & controllers

| Method / verb | Path (helper) | Action |
|---------------|---------------|--------|
| GET | `/roadmap` (`roadmap_path`) | `RoadmapController#index` |
| GET | `/roadmap/:id` (`roadmap_feature_request_path`) | `#show` |
| POST | `/roadmap/requests` (`roadmap_requests_path`) | `#create` |
| POST | `/roadmap/requests/:id/vote` (`roadmap_request_vote_path`) | `#vote` |
| POST | `/roadmap/requests/:id/comments` (`roadmap_request_comments_path`) | `#create_comment` |
| DELETE | `/roadmap/comments/:id` (`roadmap_comment_path`) | `#destroy_comment` |
| *(admin)* | `/admin/roadmap/...` (`admin_feature_requests_*`) | `Admin::FeatureRequestsController` |

- **Public board:** `RoadmapController#index`, `#show`; JSON create/vote/comment behavior per `respond_to` in each action.
- **Public index UI (`#index`):** **Guests** see search, column tabs (**`role="tablist"`** immediately below the search/create row), **`roadmap.subtitle`**, and **`roadmap.guest_footer_note`**; no nav-dropdown release-notes instructional copy (**`layouts.application.dropdown.release_notes_instructions`**). Guest **`GET /roadmap`** **`:mobile`** — same (**changelog 264** / **266**). **`roadmap.title`** in **`<h1>`** — **`release_notes_spec`** HTML-escape (**260**). **Signed-in** users: **no** top info card (removed **2026-04-08**); **`support_center_url`** / release-notes entry points remain elsewhere (e.g. avatar menu, per-card **`roadmap.release_notes_link`** on cards with **`release_note_url`**). **`roadmap_spec`** (signed-in desktop + **`:mobile`**) asserts **`role="tablist"`** appears **before** **`roadmap_column_list_considering`** and still omits dropdown release-notes instructions. Stimulus **`roadmap`** controller: create modal + tab filtering (`app/views/roadmap/index.html.erb`).
- **Admin ordering / status:** `Admin::FeatureRequestsController` (drag columns, pin, edit metadata). **`GET /admin/roadmap`**: page title + search outside **`turbo_frame_tag`** **`admin_feature_requests_main`**; **`Turbo-Frame: admin_feature_requests_main`** → **`feature_requests_index_frame`** (**`layout: false`**) so **`pin`/`move`/`destroy`** Turbo Streams (**mega #163–165**) stay scoped to the frame. Card **edit** + Kanban **edit** back/cancel use **`data-turbo-frame="_top"`** (**mega #230**). **`GET /admin/roadmap/:id/edit`**: **`h1`** + back link outside **`admin_feature_requests_edit_main`**; **`Turbo-Frame: admin_feature_requests_edit_main`** → **`feature_requests_edit_frame`** (**`layout: false`**) — **mega #231**.
- **Moderation queue:** `Admin::ContentModerationController` lists `FeatureRequest` and `FeatureRequestComment` rows in `pending_review` / flagged state.

## Severe blocklist parity (mega #55 / #195)

- **Single source of terms:** `RecruitingVisibilityService::BLOCKLIST` (frozen `%w[...]` in `app/services/recruiting_visibility_service.rb`). Matching is **substring** on **downcased** text (same idea as recruiting guild **name** checks via **`publicly_recruitable?`**).
- **Recruiting vs roadmap:** Guild directory hiding uses **`publicly_recruitable?(name)`**; roadmap uses **`matching_severe_terms(*strings)`** so **title**, **description**, and **comment body** cannot ship as **approved** public copy while containing those substrings—even when **`ContentModeration::FilterService`** would not flag profanity.
- **Model merge:** `FeatureRequest#apply_content_moderation` / `FeatureRequestComment#apply_content_moderation` combine profanity hits with **`matching_severe_terms`**, set **`moderation_status`** to **`pending`** when either path fires, and persist **`moderation_triggered_words`** as JSON (**union** of profanity + severe tokens). **`moderation_triggered_words_list`** parses the column for tests and admin display.
- **Public read path:** `RoadmapController#show` loads comments through **`feature_request_comments.visible_to_public`** (or equivalent scope) so **pending** bodies never appear on the HTML/JSON detail surface.
- **Changing the list:** Editing **`BLOCKLIST`** is a **code** change—run **`recruiting_visibility_service_spec`** (exercises every entry), **`feature_request_spec`** / **`feature_request_comment_spec`**, and **`roadmap_spec`** severe examples; consider guild create UX (`recruiting_name_warning`) and any product comms. No separate YAML file today.

## Models

- **`FeatureRequest`** — `STATUSES`, `DISPLAY_COLUMNS`, `moderation_status` (`pending`, `approved`, `rejected`, `flagged`). **`visible_to_public`** = approved only. **`before_validation :apply_content_moderation`** on create/update runs `ContentModeration::FilterService` on title + description and merges **`RecruitingVisibilityService.matching_severe_terms(title, description)`** (same **`BLOCKLIST`** as recruiting directory); pending submissions are held until moderators approve.
- **`FeatureRequestComment`** — same pattern for body: profanity filter + **`matching_severe_terms(body)`**.
- **`FeatureRequestVote`** — per-user votes; drives `vote_count` / “Popular” column.

## User-facing rules (product)

- Descriptions must meet **minimum length** (model validation) so ideas are actionable.
- **Prohibited language** is filtered before publish; blocked submissions surface `roadmap.errors.blocked_content`. Approved submissions appear on the board; pending ones wait for admin review (`roadmap.create.sent_for_review` flash when applicable).

## Specs

- `spec/requests/roadmap_spec.rb` — list, create; **guest** index omits dropdown release-notes path copy and shows **`roadmap.guest_footer_note`** + **`roadmap.subtitle`** (**Figma 56:772**); **guest** **`:mobile`** — same (**264**); **signed-in** index: **`role="tablist"`** before **`roadmap_column_list_considering`**, omits **`layouts.application.dropdown.release_notes_instructions`** (desktop + **`:mobile`** — **2026-04-08**); signed-in **`support_center_url`** on **`GET /roadmap`** — still asserted default + custom, desktop + **`:mobile`** (**276**, layout / other chrome may include URL); signed-in **`GET /roadmap/:id` (HTML)** **`support_center_url`** — **301**; **`GET .../roadmap/:id` (JSON)** unknown id → **404** + **`roadmap.not_found`** (**mega #119**); **`POST .../vote` (JSON)**; **comment + request moderation**; severe blocklist examples on create + comment.
- `spec/requests/release_notes_spec.rb` — guest **`GET /roadmap`**: **`roadmap.title`** HTML escape + **`roadmap.guest_footer_note`**; documents that the support URL / signed-in roadmap link card behavior is split across specs (**changelog 260**).
- `spec/models/feature_request_spec.rb` — scopes, visibility, severe blocklist + profanity merge into **`moderation_triggered_words`**.
- `spec/models/feature_request_comment_spec.rb` — blocked / severe body → pending.
- `spec/services/recruiting_visibility_service_spec.rb` — **`BLOCKLIST`** iteration + **`matching_severe_terms`** cases (substring, multiple hits).

**Related:** `systems/content_moderation.md` (admin queue + `FilterService`), `systems/site_settings_support_url.md` (**`support_center_url`** for the release-notes link), `systems/guilds_crud.md` / `spec/requests/guilds_spec.rb` (`recruiting_name_warning`), `overall/i18n.md` (roadmap keys in `config/locales/*/roadmap.{locale}.yml`).
