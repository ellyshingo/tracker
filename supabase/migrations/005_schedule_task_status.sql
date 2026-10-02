-- GetGrant трекер: обновление 5 — расписание занятий, статусы задач, главная страница кабинета студента.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Сначала должен быть выполнен update_04.sql. Повторный запуск безопасен.

alter table public.tracker_tasks add column if not exists status text;
update public.tracker_tasks set status = case when done then 'Готово' else 'Не начато' end where status is null;

create table if not exists public.tracker_classes (
  id text primary key default gen_random_uuid()::text,
  subject text not null, teacher text, pattern text, time_start text, time_end text, room text, sort integer,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.tracker_class_members (
  id text primary key default gen_random_uuid()::text,
  class_id text not null references public.tracker_classes(id) on delete cascade,
  student_id text not null references public.tracker_students(id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (class_id, student_id)
);
do $$
declare t text;
begin
  foreach t in array array['tracker_classes','tracker_class_members'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "staff full access" on public.%I', t);
    execute format('create policy "staff full access" on public.%I for all to authenticated using (public.tracker_is_staff()) with check (public.tracker_is_staff())', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Расписание из демо-прототипа (можно править в трекере, вкладка «Расписание»)
insert into public.tracker_classes (id, subject, teacher, pattern, time_start, time_end, room, sort) values
 ('cl-ielts','IELTS','Азиз','Пн · Ср · Пт','17:00','18:30','Бирюзовый',1),
 ('cl-aw-adv','Academic Writing (продвинутые)','Азиз','Вт · Чт','18:30','20:00','Бирюзовый',2),
 ('cl-aw-base','Academic Writing (базовый уровень)','Дина','Вт · Чт','18:30','20:00','Жёлтый',3),
 ('cl-upper','Upper-Intermediate','Дина','Пн · Ср · Пт','15:00','16:30','Жёлтый',4),
 ('cl-preielts','Pre-IELTS','Дина','Вт · Чт','16:00','17:30','Жёлтый',5),
 ('cl-grammar','Grammar Intensive','Сайкал','Пн · Ср · Пт','18:00','19:30','Оранжевый',6),
 ('cl-math','Математика','Элнур','Вт · Чт','14:00','15:30','Оранжевый',7),
 ('cl-intake','Приём заявок','Элнур','Пн · Ср · Пт','10:00','12:00','Синий',8),
 ('cl-satmath','SAT Math','Бексултан','Вт · Чт · Сб','16:00','17:30','Оранжевый',9),
 ('cl-satverbal','SAT Verbal','Умиджон','Вт · Чт · Сб','17:30','19:00','Оранжевый',10)
on conflict (id) do nothing;

create or replace function public.student_portal() returns json
language plpgsql stable security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then return null; end if;
  return json_build_object(
    'student', (select json_build_object('name', s.name, 'intake', s.intake, 'major', s.major, 'curator', s.curator, 'targets', s.targets)
                from public.tracker_students s where s.id = sid),
    'apps', coalesce((select json_agg(json_build_object(
        'id', a.id, 'uni', u.name, 'country', u.country, 'round', a.round, 'status', a.status, 'program', a.program,
        'grp', a.grp, 'tier', a.tier, 'sort', a.sort,
        'rating', coalesce(a.rating, u.rating), 'sat_range', a.sat_range, 'reqs', coalesce(a.reqs, u.reqs),
        'deadline', coalesce(a.deadline_override::text, u.deadlines ->> a.round),
        'deadline_text', coalesce(a.deadline_text, u.deadline_text), 'link', u.link)
        order by a.sort nulls last, u.name)
      from public.tracker_applications a left join public.tracker_universities u on u.id = a.uni_id
      where a.student_id = sid), '[]'::json),
    'tasks', coalesce((select json_agg(json_build_object('id', t.id, 'kind', t.kind, 'period', t.period, 'title', t.title,
        'due', t.due, 'done', t.done, 'status', coalesce(t.status, case when t.done then 'Готово' else 'Не начато' end), 'sort', t.sort)
        order by t.sort, t.created_at)
      from public.tracker_tasks t where t.student_id = sid), '[]'::json),
    'tests', coalesce((select json_agg(json_build_object('date', x.date, 'test', x.test, 'kind', x.kind,
        'sections', x.sections, 'total', x.total) order by x.date nulls first)
      from public.tracker_tests x where x.student_id = sid), '[]'::json),
    'classes', coalesce((select json_agg(json_build_object('subject', c.subject, 'teacher', c.teacher, 'pattern', c.pattern,
        'start', c.time_start, 'end', c.time_end, 'room', c.room) order by c.time_start)
      from public.tracker_classes c join public.tracker_class_members m on m.class_id = c.id
      where m.student_id = sid), '[]'::json)
  );
end $$;

create or replace function public.student_set_task_status(task_id text, new_status text) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then raise exception 'not a student'; end if;
  if new_status not in ('Не начато','В процессе','Готово') then raise exception 'bad status'; end if;
  update public.tracker_tasks set status = new_status, done = (new_status = 'Готово'), updated_at = now()
  where id = task_id and student_id = sid;
  if not found then raise exception 'not found'; end if;
end $$;

create or replace function public.student_set_task_done(task_id text, is_done boolean) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then raise exception 'not a student'; end if;
  update public.tracker_tasks set done = is_done, status = case when is_done then 'Готово' else 'Не начато' end, updated_at = now()
  where id = task_id and student_id = sid;
  if not found then raise exception 'not found'; end if;
end $$;

revoke all on function public.student_portal() from public, anon;
revoke all on function public.student_set_task_status(text, text) from public, anon;
revoke all on function public.student_set_task_done(text, boolean) from public, anon;
grant execute on function public.student_portal() to authenticated;
grant execute on function public.student_set_task_status(text, text) to authenticated;
grant execute on function public.student_set_task_done(text, boolean) to authenticated;
