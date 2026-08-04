# code_map_for_devs

**Purpose:** Current developer maps for GuildSync subsystems and how they connect.

**Location:** Repository root (`GuildSync/code_map_for_devs/`), outside the Rails
app (`guildsync/`). These maps stay in the application repository because they
are active development references.

Historical implementation notes, AI artifacts, bug-fix reports, old review
outputs, prompt archives, and retired planning docs belong in the separate
knowledge-base repository:

`git@github.com:Th3B0W3RY/guildsync_knowledge_base.git`

## Start Here

- [`overall/app_flow_end_to_end.md`](overall/app_flow_end_to_end.md) — app topology and reading order.
- [`INDEX.md`](INDEX.md) — current map inventory.

## Conventions

- `systems/` — one focused topic per file: models, routes, policies, jobs,
  external APIs, failure modes, and spec pointers.
- `overall/` — cross-cutting flows such as auth, billing, request lifecycle,
  i18n, storage, background jobs, and deploy.
- `INDEX.md` — file list and last-updated date. Refresh the row for every map
  you edit or add.

## Maintenance

- Any application or test change that alters behavior, routes, authorization,
  jobs, integrations, or important developer navigation should trigger a
  conscious pass over these maps.
- Update the smallest relevant map. Avoid broad rewrites and historical
  changelog dumps.
- Keep maps factual and current; do not store "how we fixed this" narratives
  here. Move those to `guildsync_knowledge_base`.
- Keep file count practical: roughly 60 `systems/` pages and 20 `overall/`
  pages unless the app genuinely outgrows that shape.

**Last updated:** 2026-05-21
