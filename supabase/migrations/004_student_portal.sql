-- GetGrant трекер: обновление 4 — личный кабинет студента.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- Студент видит ТОЛЬКО то, что отдают функции ниже: свои вузы, задачи и баллы.
-- Заметки, стратегия, встречи, комментарии к тестам, отчёты ему недоступны даже при прямом запросе к базе.

alter table public.tracker_students add column if not exists student_email text;
create unique index if not exists tracker_students_email_uq on public.tracker_students (lower(student_email)) where student_email is not null and student_email <> '';

create or replace function public.tracker_my_student_id() returns text
language sql stable security definer set search_path = public as $$
  select id from public.tracker_students
  where student_email is not null and lower(student_email) = lower(auth.jwt() ->> 'email')
  limit 1;
$$;

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
        'deadline', coalesce(a.deadline_override::text, u.deadlines ->> a.round),
        'deadline_text', coalesce(a.deadline_text, u.deadline_text), 'link', u.link)
        order by a.sort nulls last, u.name)
      from public.tracker_applications a left join public.tracker_universities u on u.id = a.uni_id
      where a.student_id = sid), '[]'::json),
    'tasks', coalesce((select json_agg(json_build_object('id', t.id, 'kind', t.kind, 'period', t.period, 'title', t.title,
        'due', t.due, 'done', t.done, 'sort', t.sort) order by t.sort, t.created_at)
      from public.tracker_tasks t where t.student_id = sid), '[]'::json),
    'tests', coalesce((select json_agg(json_build_object('date', x.date, 'test', x.test, 'kind', x.kind,
        'sections', x.sections, 'total', x.total) order by x.date nulls first)
      from public.tracker_tests x where x.student_id = sid), '[]'::json)
  );
end $$;

create or replace function public.student_set_app_status(app_id text, new_status text) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then raise exception 'not a student'; end if;
  if new_status not in ('Планируем','Готовим','Подано','Интервью','Принят','Лист ожидания','Отказ','Отозвано') then
    raise exception 'bad status';
  end if;
  update public.tracker_applications set status = new_status, updated_at = now()
  where id = app_id and student_id = sid;
  if not found then raise exception 'not found'; end if;
end $$;

create or replace function public.student_set_task_done(task_id text, is_done boolean) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then raise exception 'not a student'; end if;
  update public.tracker_tasks set done = is_done, updated_at = now()
  where id = task_id and student_id = sid;
  if not found then raise exception 'not found'; end if;
end $$;

revoke all on function public.student_portal() from public, anon;
revoke all on function public.student_set_app_status(text, text) from public, anon;
revoke all on function public.student_set_task_done(text, boolean) from public, anon;
revoke all on function public.tracker_my_student_id() from public, anon;
grant execute on function public.student_portal() to authenticated;
grant execute on function public.student_set_app_status(text, text) to authenticated;
grant execute on function public.student_set_task_done(text, boolean) to authenticated;
grant execute on function public.tracker_my_student_id() to authenticated;
