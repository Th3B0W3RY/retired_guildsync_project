# GuildSync archive documentation boundary

This retired public repository contains only the application snapshot and the
documentation required to understand it. Internal knowledge bases, local
automation configuration, and private repository locations are intentionally
not published here.

Keep the following outside this public archive:

- AI assistance artifacts
- Bug-fix reports, RCA notes, and audit JSON
- Formal code review outputs
- Implementation reports and historical plans
- QA investigations and historical test audits
- Prompt archives and prior workflow notes
- Retrospectives and "how this was fixed" documentation

Keep this application repository focused on the live app:

- Rails source, specs, migrations, assets, and runtime config
- GitHub Actions, deploy scripts, and production maintenance files
- Setup docs required to run, test, deploy, and maintain the app
- Current developer maps under `code_map_for_devs/`
- Archive-safe contributor guidance in `AGENTS.md`
- Public documentation required to understand the snapshot

## Artifact policy

When work produces a non-runtime artifact, store it in an access-controlled
workspace chosen by the repository owner. Do not publish private clone URLs,
credentials, machine-specific paths, audit exports, or prompt transcripts.

Current app maps remain in `code_map_for_devs/`. If app behavior, routes,
authorization, jobs, integrations, or important developer navigation changes,
update the smallest relevant app map here. Move only historical narrative and
artifact-heavy notes to the knowledge base.

## Local Scratch

The app repo still ignores `/ai_db/` as local scratch space. Do not treat it as
the durable artifact home; migrate durable reports and notes to
`guildsync_knowledge_base`.
