# Admin database queries (read-only)

**Last updated:** 2026-04-06

## Purpose

Saved **SELECT** templates plus a guarded custom **SELECT** box for support (`Admin::QueriesController`). Execution is audited; custom SQL must start with **SELECT** and must not contain blocked DDL/DML keywords.

## Turbo

- **`GET /admin/queries`** with **`Turbo-Frame: admin_queries_index_main`** (constant **`Admin::QueriesController::QUERIES_INDEX_MAIN_FRAME`**) renders **`queries_index_main_frame`** (**`layout: false`**) wrapping **`_queries_index_main`** (saved runs, custom SQL form, **`admin_queries_results_wrap`**). Full-page **`index`** keeps the page title, back link, and **`admin_queries_flash`** outside the frame.
- **`POST /admin/queries/execute`** with **`Accept: text/vnd.turbo-stream.html`** renders **`queries_execute_refresh.turbo_stream.erb`**, which **`replace`**s **`admin_queries_results_wrap`** with **`_results_panel`** (results and/or execution error). Invalid selection (no saved key / no custom SQL) → **`303`** redirect to **`admin_queries_path`** + flash.
- **`admin/queries/index`**: **`button_to`** run buttons and custom query **`form_with`** use Turbo (no **`data-turbo: false`**).

## Key paths

| Piece | Path |
|-------|------|
| Controller | `guildsync/app/controllers/admin/queries_controller.rb` |
| Views | `guildsync/app/views/admin/queries/index.html.erb`, `_queries_index_main.html.erb`, `queries_index_main_frame.html.erb`, `_results_panel.html.erb`, `queries_execute_refresh.turbo_stream.erb` |
| Spec | `spec/requests/admin/queries_spec.rb` |

**Related:** `systems/admin_dashboard.md`, `overall/request_specs_and_gates.md`.
