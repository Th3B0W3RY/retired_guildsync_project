# Home landing marketing CMS

**Last updated:** 2026-04-11 (**production DB is source of truth** for feature cards, homepage footer support URLs, standalone legal pages, and compare tables; **`deploy/deploy.sh`** does **not** run YAML import; **`landing_marketing:import`** requires **`FORCE_LANDING_MARKETING_IMPORT=1`** in production; optional **`marketing_snapshot.yml`** export/import for backup & dev only; dev session cookie **`domain: nil`** — **`config/application.rb`**)

## Purpose

This subsystem lets admins manage the guest-homepage marketing content. **In production, the database is the source of truth** for **Homepage feature cards**, **feature detail pages** (`/features/:slug`), **homepage footer support links**, **standalone legal pages**, **GuildSync vs …** tables, and comparison rows — admin edits persist across deploys; **Git/YAML must not overwrite** them automatically. **User feedback** is also DB-only. Optional YAML tooling is for **backup, dev seed, staging reset, or explicit recovery** only (see **Optional YAML snapshot** below).

- A rich-text User Feedback carousel rendered **after** the Features headline + card grid (admin-managed; order is hero → features → testimonials).
- Homepage feature cards that are fully clickable and route to dedicated public detail pages at `/features/:slug`.
- **GuildSync vs …** comparison tables on the landing page: **`LandingCompare::Repository`** reads the **DB** when **`LandingComparisonTable`** is fully populated (three tables, each with rows); otherwise it falls back to **i18n + `LandingCompare::Catalog`** (static defaults — not YAML). Admins edit via **Admin → GuildSync vs Competitors** (`Admin::LandingCompareController`). **`#edit`** calls **`LandingCompare::SeedDefaults.seed!`** when **`!fully_seeded?`** so an empty DB gets the three default tables and rows (same catalog as migrations) without YAML deploy import.
- Admin CRUD, visibility toggles, and drag-reorder tools for feature cards, feedback, and compare tables.

## Public entry points

- `GET /` → `HomeController#landing`
- `GET /features/:slug` → `HomepageFeaturesController#show`
- `GET /support/documentation` → `FooterSupportLinksController#documentation`
- `GET /support/contact-link` → `FooterSupportLinksController#contact`
- `GET /support/discord` → `FooterSupportLinksController#discord`
- `GET /privacy` → `MarketingLegalPagesController#show`
- `GET /terms` → `MarketingLegalPagesController#show`
- `GET /security` → `MarketingLegalPagesController#show`

**Mobile layout parity:** `application.html+mobile.erb` treats **`homepage_features#show`** like other guest marketing surfaces (`marketing_flush_shell` + Inter preconnect), matching `application.html.erb` so feature detail pages are not trapped in the generic “card in a box” wrapper on phone UAs.

`HomeController#landing` loads:

- `@landing_user_feedbacks = LandingUserFeedback.visible.with_rich_text_body.ordered.limit(LandingUserFeedback::MAX_ENTRIES).to_a`
- `@homepage_feature_cards = HomepageFeatureCard.visible.ordered.to_a`

**Hero** (`home/landing.html.erb`): **`home.landing.title`** as **`h1`** (**`text-5xl sm:text-6xl lg:text-6xl`**, **`w-full max-w-none`**, **`text-balance`**); EN/DE titles end with **`.`**; **`home.landing.subtitle`** as **`p`** (**`text-lg sm:text-xl lg:text-2xl`**, **`text-balance`**, **`max-w-6xl`**); EN/DE subtitles are **one sentence** ending with **`.`**; **`min-h-[32rem] md:min-h-[42rem]`** on **`landing-hero-cinematic`**.

The landing page renders **`home/landing_features_section`** immediately under the hero: **`home.landing.why_title`** as a large display **`h2`** (**`clamp(1.85rem,7vw,4.5rem)`**), then **`home.landing.features_cta_hint`** as **`h3`**, subtitle **`p`**, then **`#features`** grid. Section **`aria-labelledby`** targets **`landing-why-guildsync-heading`**. Padding **`pt-12 sm:pt-16 md:pt-20 pb-20 sm:pb-24`**; hero column ends with **`pb-10 sm:pb-12 md:pb-14`** ( **`why_title`** no longer inside the video hero). Then **`home/landing_user_feedback_section`** when visible feedback rows exist; feedback uses **`pt-12 sm:pt-14`** top.

Homepage footer behavior now splits cleanly by section:

- **Product** remains internal: `#features`, `pricing_path`, `roadmap_path`
- **Support** uses internal redirect routes so admins can manage DB-backed external URLs independently: documentation, contact, Discord
- **Legal** uses standalone rich-text pages at `/privacy`, `/terms`, and `/security`

## Models

### `LandingUserFeedback`

**Path:** `guildsync/app/models/landing_user_feedback.rb`

- `has_rich_text :body`
- `MAX_ENTRIES = 25`
- Validates `body` presence
- Enforces the 25-entry cap on create only via `entry_limit_not_exceeded`
- Scopes: `visible`, `ordered`

### `HomepageFeatureCard`

**Path:** `guildsync/app/models/homepage_feature_card.rb`

- `has_rich_text :body`
- Fields: `slug`, `title`, `description`, `icon_key`, `position`, `visible`
- Uses `slug` as the public identifier via `to_param`
- `before_validation :normalize_slug` lowercases and trims the slug
- Validates slug format with `/\A[a-z][a-z0-9_]*\z/`
- Scopes: `visible`, `ordered`
- **`ICON_KEYS`** includes **`custom_role_system`** (key icon in **`home/_feature_icon_svg`**); **`home.landing.features_grid.custom_role_system`** in all **10** guest locales

### `MarketingLegalPage`

**Path:** `guildsync/app/models/marketing_legal_page.rb`

- `has_rich_text :body`
- Fixed kinds: `privacy`, `terms`, `security`
- Uses `kind` as the public/admin identifier via `to_param`
- `ensure_defaults!` backfills the required rows when an environment was created from schema without migration data
- `for_kind!` is the canonical public/admin lookup entry point

## Public UI

### Features headline + grid

- Partial: `guildsync/app/views/home/_landing_features_section.html.erb` — rendered from `home/landing.html.erb` right after the hero (**`why_title`** + features CTA + **`#features`** grid); **`#features`** id stays on the grid for footer deep links.

### Feedback carousel

- View partial: `guildsync/app/views/home/_landing_user_feedback_section.html.erb`
- Section **`h2`** + region **`aria-label`**: **`home.landing.feedback.section_title`** (EN: **“What our users think!”**; translated in all **10** guest locales)
- Carousel panel: generous vertical padding (**`py-12 sm:py-16 md:py-20`**), **`min-h-[14rem] sm:min-h-[17rem] md:min-h-[20rem]`**, **`flex`** + **`justify-center`** so short quotes still sit in a tall, prominent frame; body copy **`text-base sm:text-lg`**
- Stimulus controller: `guildsync/app/javascript/controllers/landing_feedback_carousel_controller.js`
- Interval: **`SiteSetting.landing_feedback_carousel_interval_ms`** (default **6000** ms) via `data-landing-feedback-carousel-interval-value`
- Prev/next/dot controls (when **>1** slide): `home.landing.feedback.previous`, **`next`**, **`pagination`**, **`go_to_slide`** (**%{index}**) in **all 10 guest locales** (no inline `default:` fallbacks in the template)
- Live-region announcement template: `data-landing-feedback-carousel-announce-template-value`
- Behavior: auto-advance, hover pause, keyboard arrows, swipe support, reduced-motion autoplay disable, polite progress announcements with a content snippet; **ResizeObserver** on the slide viewport + **`getBoundingClientRect`** fallbacks in **`slideWidth()`** so **`translateX`** uses real widths after layout (fixes Windows/Chrome first-paint **`clientWidth === 0`**); double **`requestAnimationFrame`** reapplies transform after connect
- Focus behavior: autoplay pauses when focus is on a **descendant** (prev/next/dot, links in copy); focus on the **region root** (`tabindex="0"` section) does **not** pause so Windows initial focus does not stop the ticker; **`focusout`** resumes when focus leaves the region

### Homepage feature cards

- Card partial: `guildsync/app/views/home/_homepage_feature_card.html.erb`
- Entire card is wrapped in `link_to homepage_feature_path(card.slug)` with `block h-full w-full` so the full tile is clickable and fills the grid cell; the features grid uses `items-stretch` for equal-height rows
- **Hover:** Tailwind `group` + `hover:border-[#7C86FF]`, layered purple/violet `box-shadow`, slight `translate-y` and background lift, icon `group-hover:scale-105` + glow; `motion-reduce:*` disables motion for prefers-reduced-motion
- Block header: **`h2`** `home.landing.why_title` (display scale); **`h3`** `home.landing.features_cta_hint` (**`text-4xl sm:text-5xl lg:text-[3.25rem]`**); **`p`** `home.landing.features_section_subtitle` (**`text-lg sm:text-xl lg:text-2xl`**); `home_landing_spec` asserts **`why_title`** in **`h2`** and CTA in **`h3`**

### Feature detail page

- Controller: `guildsync/app/controllers/homepage_features_controller.rb`
- View: `guildsync/app/views/homepage_features/show.html.erb`
- Only visible cards resolve publicly; hidden cards return `404`
- Detail content is stored in ActionText and rendered as rich text, leaving room for future richer media support
- **`show`** head tags: **`meta description`**, **`og:type`** (**website**), **`og:url`**, **`og:title`**, **`og:description`**, **`og:image`** (absolute URL to **`favicon/apple-touch-icon-1024x1024.png`**), **`twitter:card`** (**summary**) + matching title/description/image, **`rel="canonical"`** (aligned with **`og:url`**)
- **`HomepageFeaturesController#show`** uses **`with_rich_text_body`** so the detail body loads without an extra round-trip
- **`HomepageFeatureCard#detail_body_present?`**: treats empty Trix/HTML as absent so the public page shows **`homepage_features.empty_detail`** instead of a blank rich-text shell; `homepage_feature_card_spec` covers it

## Admin CMS

### Turbo dashboard frame (no “Content missing”)

- Concern: `guildsync/app/controllers/concerns/admin/turbo_dashboard_frame.rb` — **`respond_with_dashboard_frame(template)`** when **`Turbo-Frame: admin_dashboard_index_main`** matches **`Admin::DashboardController::DASHBOARD_INDEX_MAIN_FRAME`**
- Used by **`Admin::LandingUserFeedbacksController`** and **`Admin::HomepageFeatureCardsController`** for **index / new / edit**; frame variants live at **`*_frame.html.erb`** wrapping the same inner template in **`turbo_frame_tag`**
- Forms and destructive actions use **`data-turbo-frame="_top"`** so submits escape the dashboard frame

### Dashboard grouping

- **`admin.dashboard.homepage_cms.title`** / **`subtitle`** — glass block **Homepage & guest marketing** in **`_dashboard_main.html.erb`** groups **Landing compare**, **User feedback**, and **Homepage feature cards** links

### Dashboard quick actions

- `admin.dashboard.quick_actions.user_feedback_manager`
- `admin.dashboard.quick_actions.homepage_feature_cards`

Rendered from `guildsync/app/views/admin/dashboard/_dashboard_main.html.erb`.

### User Feedback Manager

- Controller: `guildsync/app/controllers/admin/landing_user_feedbacks_controller.rb`
- Views: `guildsync/app/views/admin/landing_user_feedbacks/*`
- Routes:
  - `GET /admin/landing-user-feedbacks`
  - `GET /admin/landing-user-feedbacks/new`
  - `POST /admin/landing-user-feedbacks`
  - `GET /admin/landing-user-feedbacks/:id/edit`
  - `PATCH /admin/landing-user-feedbacks/:id`
  - `DELETE /admin/landing-user-feedbacks/:id`
  - `PATCH /admin/landing-user-feedbacks/reorder`
- Supports: create, edit, delete, enable/disable (`visible`), rich text body, drag reorder, 25-entry cap enforcement
- **`PATCH …/reorder`** only applies when **`params[:order]`** is a **permutation of every row id** (`complete_reorder_payload?`); otherwise **`422`** with empty body and **no** position writes

### Home Page Feature Cards/Pages Editor

- Controller: `guildsync/app/controllers/admin/homepage_feature_cards_controller.rb`
- Views: `guildsync/app/views/admin/homepage_feature_cards/*`
- Routes:
  - `GET /admin/homepage-feature-cards`
  - `GET /admin/homepage-feature-cards/new`
  - `POST /admin/homepage-feature-cards`
  - `GET /admin/homepage-feature-cards/:id/edit`
  - `PATCH /admin/homepage-feature-cards/:id`
  - `DELETE /admin/homepage-feature-cards/:id`
  - `PATCH /admin/homepage-feature-cards/reorder`
- `POST /admin/homepage-feature-cards/upload_image` (admin-only image uploads used by the editor toolbar)
- Supports: card metadata, visibility toggle, ordering (same **`complete_reorder_payload?`** rule as feedback), ActionText detail-page body, and slug-managed public pages
- Admin edit/update/delete lookup accepts slug route params (from `to_param`) instead of numeric id only, fixing blank/404 edit pages from `/admin/homepage-feature-cards/:slug/edit`
- Body editing now reuses the same Stimulus `editor` controller and toolbar used by Guild Documents, with `output_format=html` for ActionText compatibility
- Toolbar image uploads use the admin endpoint above and store via Active Storage (S3 in production) using the same service configuration as Guild Document image uploads
- Admin index includes a `view_public` action linking to `homepage_feature_path(card.slug)` in a new tab for quick QA of the public page

### Footer Links & Legal Pages

- Controller: `guildsync/app/controllers/admin/homepage_footer_settings_controller.rb`
- View: `guildsync/app/views/admin/homepage_footer_settings/show.html.erb`
- Routes:
  - `GET /admin/homepage-footer`
  - `PATCH /admin/homepage-footer`
- Supports:
  - DB-backed external URLs for footer Documentation, Contact, and Discord
  - Public QA links from admin
  - Entry points into the legal-page editor
- Audit action: `update_homepage_footer_support_links`

### Legal page editor

- Controller: `guildsync/app/controllers/admin/marketing_legal_pages_controller.rb`
- Views: `guildsync/app/views/admin/marketing_legal_pages/*`
- Routes:
  - `GET /admin/marketing-legal-pages/:id/edit`
  - `PATCH /admin/marketing-legal-pages/:id`
- Supports title + ActionText body editing for Privacy, Terms, and Security
- Audit action: `update_marketing_legal_page`

## JavaScript and rich text wiring

- `guildsync/app/javascript/application.js` imports `trix`, `@rails/actiontext`, Turbo, and Stimulus controllers
- `guildsync/app/assets/stylesheets/application.tailwind.css` imports `trix/dist/trix.css`
- Reordering is handled by `admin-order-list` via HTML5 drag-and-drop and `PATCH reorder`

## Data and seeds

- Migration: `guildsync/db/migrate/20260406183100_create_landing_user_feedbacks_and_homepage_feature_cards.rb`
- Data migration (runs on `db:migrate`): `guildsync/db/migrate/20260406183200_seed_homepage_feature_cards_from_i18n.rb` — when **`homepage_feature_cards`** is empty, inserts every **`features_grid`** slug from **EN i18n** (titles + descriptions, **`body`** blank until admins edit). **`down`** uses **`find_each(&:destroy!)`** so **`ActionText`** rows are not orphaned.
- Follow-up: `guildsync/db/migrate/20260407120000_add_custom_role_system_homepage_card_and_refresh_compare_tables.rb` — inserts **`custom_role_system`** if missing ( **`position`** after current max), then **`LandingCompare::Catalog.rebuild_rows_for_table!`** on each **`LandingComparisonTable`** so new catalog rows (e.g. **Custom Role System**: GuildSync ✓, all competitor columns ✗) appear. **`down`** removes that card and the compare row labeled **Custom Role System**, then re-packs row **`position`**.
- **`LandingCompare::Catalog`** (`guildsync/app/services/landing_compare/catalog.rb`): canonical list of default compare-row keys, English labels, and per-competitor booleans; **`rebuild_rows_for_table!`** replaces all rows for a table (admin edits are overwritten when this runs in a migration).
- Development sample seed: `guildsync/db/seeds/landing_marketing_cms_development.rb` (loaded from **`db/seeds.rb`** in **development** only) — idempotent **`LandingUserFeedback`** samples when that table is empty; **also** inserts **four** demo feature cards with **ActionText bodies** only if **`homepage_feature_cards`** is still empty (e.g. **`db:schema:load`** without the data migration). After the i18n seed migration has run, the feature-card branch is skipped so local DBs are not duplicated.

### Optional YAML snapshot (non-authoritative in production)

- **File:** `guildsync/config/landing/marketing_snapshot.yml` — **`version: 1`**, **`homepage_feature_cards`**, **`landing_comparison_tables`** (same shape as before).
- **Export:** `bin/rails landing_marketing:export` — writes YAML from the DB (**development** or **test** only). Use for backups or to refresh the committed template; **not** required for production runtime.
- **Import:** `bin/rails landing_marketing:import` — **destructive replace** of feature cards + compare tables from the file. In **`production`**, **`LandingMarketing::Snapshot::Importer`** raises unless **`FORCE_LANDING_MARKETING_IMPORT=1`** is set (intentional operator action). Does **not** touch **`LandingUserFeedback`** or **`SiteSetting`**.
- **Baseline:** `bin/rails landing_marketing:write_baseline` — regenerates the YAML from **EN i18n** + **`LandingCompare::Catalog`** (no DB read).
- **Code:** `guildsync/app/services/landing_marketing/snapshot/{paths,baseline,exporter,importer}.rb`; **rake:** `guildsync/lib/tasks/landing_marketing.rake`.
- **Deploy:** `deploy/deploy.sh` does **not** run import; production CMS data is untouched by deploy.

## Specs

- `guildsync/spec/requests/home_landing_spec.rb` (snapshot import smoke in **test**; **DB authoritative title** example)
- `guildsync/spec/requests/homepage_footer_links_spec.rb`
- `guildsync/spec/services/landing_marketing/snapshot/importer_spec.rb`
- `guildsync/spec/requests/home_landing_marketing_contract_spec.rb`
- `guildsync/spec/requests/homepage_features_spec.rb`
- `guildsync/spec/requests/admin/homepage_footer_settings_spec.rb`
- `guildsync/spec/requests/admin/landing_marketing_cms_spec.rb` (guest → **`admin_login_path`** on index / **new** / **edit** / all mutating routes; signed-in **CRUD** + **reorder**; **reorder** **422** when id list is not a full permutation)
- `guildsync/spec/requests/admin/landing_marketing_cms_management_spec.rb` (signed-in **at_limit** **`new`**, visibility → public **404**, delete → public **404**)
- `guildsync/spec/requests/admin/landing_marketing_cms_reorder_spec.rb`
- `guildsync/spec/requests/admin/homepage_marketing_cms_spec.rb` (Turbo-Frame GETs for feature cards + feedbacks **index** return matching frame)
- `guildsync/spec/requests/admin/dashboard_spec.rb` (homepage CMS block + links; use **HTML-escaped** expectations for strings containing **`&`**)
- `guildsync/spec/models/homepage_feature_card_spec.rb`
- `guildsync/spec/models/landing_user_feedback_spec.rb`
- `guildsync/spec/models/marketing_legal_page_spec.rb`
- `guildsync/spec/lib/landing_marketing_cms_development_seed_spec.rb`
- `guildsync/spec/lib/deploy_script_landing_marketing_spec.rb` (deploy must not auto-run `landing_marketing:import`)
- `guildsync/spec/i18n/home_landing_feedback_i18n_spec.rb` (carousel **`home.landing.feedback.*`** keys in all locales)
- `guildsync/spec/services/landing_compare/catalog_spec.rb` (**`custom_role_system`** catalog defaults)

## Failure modes and notes

- Empty **`homepage_feature_cards`**: the grid is empty until admins create cards, the **i18n data migration** has run (one-time empty table), or (development) the sample seed fills demo cards when the table is empty. **Production:** content stays whatever is in the DB across deploys; use **`landing_marketing:import`** with **`FORCE_LANDING_MARKETING_IMPORT=1`** only for deliberate disaster recovery.
- Hidden feature cards: `/features/:slug` returns `404`.
- Feedback entries above the cap: model validation blocks create and the admin UI disables further creation.
- Missing CMS tables in local/dev setup: the development seed script exits early with a skip message instead of raising.
- Be cautious editing `app/views/home/landing.html.erb`, `app/views/home/_landing_user_feedback_section.html.erb`, and locale files during parallel work because those files are common collision points in homepage feature work.
