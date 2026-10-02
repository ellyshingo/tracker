-- 002: тесты, задачи, встречи, поля для отчёта.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.

alter table public.tracker_students add column if not exists checklist jsonb not null default '{}'::jsonb;
alter table public.tracker_students add column if not exists metrics jsonb not null default '[]'::jsonb;
alter table public.tracker_students add column if not exists targets jsonb not null default '{}'::jsonb;
alter table public.tracker_students add column if not exists tier_titles jsonb not null default '{}'::jsonb;
alter table public.tracker_students add column if not exists strategy text;
alter table public.tracker_students add column if not exists done_list text;
alter table public.tracker_students add column if not exists strengths text;
alter table public.tracker_students add column if not exists weaknesses text;
alter table public.tracker_students add column if not exists curator_notes text;
alter table public.tracker_students add column if not exists unis_note text;

alter table public.tracker_universities add column if not exists rating text;
alter table public.tracker_universities add column if not exists aid text;
alter table public.tracker_universities add column if not exists deadline_text text;

alter table public.tracker_applications add column if not exists tier text;
alter table public.tracker_applications add column if not exists note text;

create table if not exists public.tracker_tests (
  id text primary key default gen_random_uuid()::text,
  student_id text not null references public.tracker_students(id) on delete cascade,
  date date, test text not null, kind text, sections jsonb not null default '{}'::jsonb,
  total text, comment text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.tracker_tasks (
  id text primary key default gen_random_uuid()::text,
  student_id text not null references public.tracker_students(id) on delete cascade,
  kind text not null default 'prep', period text, title text not null, due date,
  done boolean not null default false, sort integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.tracker_meetings (
  id text primary key default gen_random_uuid()::text,
  student_id text not null references public.tracker_students(id) on delete cascade,
  date date, author text, notes text, next_steps text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists tracker_tests_student_idx on public.tracker_tests(student_id);
create index if not exists tracker_tasks_student_idx on public.tracker_tasks(student_id);
create index if not exists tracker_meetings_student_idx on public.tracker_meetings(student_id);

do $$
declare t text;
begin
  foreach t in array array['tracker_tests','tracker_tasks','tracker_meetings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "staff full access" on public.%I', t);
    execute format('create policy "staff full access" on public.%I for all to authenticated using (public.tracker_is_staff()) with check (public.tracker_is_staff())', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
