-- GetGrant трекер: таблицы, доступ и realtime.
-- Запустите целиком в Supabase → SQL Editor → New query → Run.

create table if not exists public.tracker_staff (
  email text primary key,
  name  text,
  added_at timestamptz not null default now()
);

create table if not exists public.tracker_students (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  grade text, intake text, type text, status text, curator text,
  grad_year text, major text, countries text,
  ielts text, toefl text, sat text, ort text, gpa text,
  contact text, parent text, notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tracker_universities (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  country text, link text,
  deadlines jsonb not null default '{}'::jsonb,   -- {"ED":"2026-11-01","RD":"2027-01-01",...}
  reqs text, notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tracker_applications (
  id text primary key default gen_random_uuid()::text,
  student_id text not null references public.tracker_students(id) on delete cascade,
  uni_id text references public.tracker_universities(id) on delete restrict,
  program text, round text, deadline_override date, status text,
  essay text, supp text, recs text, docs text, scores text,
  result text, amount text, notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tracker_applications_student_idx on public.tracker_applications(student_id);
create index if not exists tracker_applications_uni_idx on public.tracker_applications(uni_id);

create table if not exists public.tracker_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Доступ: только сотрудники из tracker_staff (по email входа).
create or replace function public.tracker_is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.tracker_staff where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

alter table public.tracker_staff        enable row level security;
alter table public.tracker_students     enable row level security;
alter table public.tracker_universities enable row level security;
alter table public.tracker_applications enable row level security;
alter table public.tracker_settings     enable row level security;

drop policy if exists "staff read own row" on public.tracker_staff;
create policy "staff read own row" on public.tracker_staff
  for select to authenticated using (lower(email) = lower(auth.jwt() ->> 'email'));

do $$
declare t text;
begin
  foreach t in array array['tracker_students','tracker_universities','tracker_applications','tracker_settings'] loop
    execute format('drop policy if exists "staff full access" on public.%I', t);
    execute format('create policy "staff full access" on public.%I for all to authenticated using (public.tracker_is_staff()) with check (public.tracker_is_staff())', t);
  end loop;
end $$;

-- Живые обновления у всей команды.
do $$
declare t text;
begin
  foreach t in array array['tracker_students','tracker_universities','tracker_applications','tracker_settings'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
