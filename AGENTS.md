# AGENTS.md — GetGrant Tracker

Instructions for coding agents (Codex, Claude Code, etc.) working in this repository.

## What this is
Internal tool for GetGrant, an admissions-consulting center in Bishkek (~50 students applying abroad).
- `index.html` — **curator tracker** (staff only): students, applications, university catalog, tests, tasks, meetings, schedule, PDF/Word report generation.
- `student.html` — **student portal** (mobile-first): own universities (can change status), plan/tasks (can change status), tests, class schedule.
- `config.js` — Supabase URL + **anon** key (public by design; security is enforced by RLS).
- `supabase/migrations/NNN_*.sql` — database schema, applied manually in Supabase → SQL Editor, in order.
- `supabase/functions/drive/index.ts` — Edge Function: student documents on the center's Google Drive (list/upload/download/visibility/delete/purge). Deployed by the owner via Supabase dashboard → Edge Functions (editor) — paste the file, name `drive`.

The UI language is **Russian**. Keep all user-facing text in Russian.

## Architecture
- No build step, no framework, no npm. Each page is a single self-contained HTML file with inline CSS and vanilla JS inside one IIFE.
- Only external scripts: `@supabase/supabase-js@2` UMD from jsDelivr, Google Fonts (Onest, Unbounded).
- Hosting: GitHub Pages from the `main` branch root. Merging to `main` deploys.
- Backend: Supabase (Postgres + Auth + Realtime). Free tier.

## Data model (public schema, all tables prefixed `tracker_`)
| Table | Purpose |
|---|---|
| `tracker_staff` | emails allowed to use the curator tracker |
| `tracker_students` | student card; `student_email` links a login to a student; json fields `checklist`, `metrics`, `targets`, `tier_titles`, `report_opts`, `group_notes` |
| `tracker_universities` | shared catalog; `deadlines` jsonb `{round: ISO date}`, `rating`, `aid`, `reqs`, `deadline_text` |
| `tracker_applications` | student × university; `round`, `status`, `tier`, `grp` + `sort` (report grouping/order), per-student overrides `rating`, `sat_range`, `reqs`, `deadline_text`, `aid`, `note`, `deadline_override` |
| `tracker_tests` | test attempts (IELTS/SAT/TOEFL/ОРТ…), `kind` Пробный/Официальный, `sections` jsonb, `total`, `comment` |
| `tracker_tasks` | `kind` prep/timeline, `period`, `title`, `due`, `done`, `status` (Не начато/В процессе/Готово), `sort` |
| `tracker_meetings` | curator meeting log |
| `tracker_classes`, `tracker_class_members` | class schedule and group membership |
| `tracker_settings` | key/value (`lists` → curators) |
| `tracker_students.drive_folder_id` | Google Drive folder of the student (set only via `drive_set_folder()` or the function) |

JS uses camelCase; DB uses snake_case. Mapping lives in `FIELD`/`COLS`/`toRow`/`fromRow` in `index.html` — **add every new column there** or it will be silently dropped on save.

## Security rules (do not break)
1. Staff access: RLS policy `"staff full access"` using `public.tracker_is_staff()` on every staff table. Every new table must enable RLS and get this policy.
2. Students NEVER read tables directly. They only call `SECURITY DEFINER` functions: `student_portal()`, `student_set_app_status()`, `student_set_task_status()`, `student_set_task_done()`. These return/modify only the caller's own rows and must never expose curator-only fields (notes, strategy, strengths/weaknesses, curator_notes, meetings, test comments, app notes).
3. Never commit the Supabase `service_role` key or any student personal data (names, scores, notes) to this repo. Real data lives only in Supabase.
4. Escape all user/DB text with `esc()` before inserting into HTML.
5. Documents: files live on the center's Google Drive; browsers never get Google credentials. Every Drive operation goes through `supabase/functions/drive`, which asks the DB (`drive_access()`) who the caller is. Students see only files with `appProperties.gg_vis = "1"`, may delete only their own uploads (`gg_src = "student"`), never get Drive links. Every file operation must check the file is inside the student's folder (`insideFolder`). Google secrets live only in Supabase → Edge Functions → Secrets.
   Function tests: `node --experimental-strip-types supabase/functions/drive/test.mjs` (mocks Google + PostgREST). Keep it passing and extend it for new actions.

## Making changes
- Schema change → add a **new** file `supabase/migrations/NNN_description.sql` (next number). Make it idempotent (`if not exists`, `create or replace`, `on conflict do nothing`). Never edit already-applied migrations. Mention in the PR that the owner must run it in Supabase SQL Editor **before** merging the HTML.
- Keep pages working at 390px phone width (no horizontal scroll) and in dark mode (colors via CSS variables in `:root`).
- Status lists (`STATUS`, `TASK_ST`, `ROUNDS`, `TIERS`, `INTAKES`, `COUNTRIES`, `REGION_OF`) are defined near the top of each page's script; keep `student.html` and the SQL functions' allowed values in sync with them.
- Run a syntax check before committing: extract the inline script and run `node --check`.

## Testing locally
Open the HTML files via a static server (`python3 -m http.server`) with a `config.js` pointing to a **test** Supabase project, or stub `window.supabase` as in prior tests. Do not test against production data.

## Owner
Non-technical owner. In PR descriptions, explain changes in plain Russian and list exact manual steps (which SQL to run, what to click).
