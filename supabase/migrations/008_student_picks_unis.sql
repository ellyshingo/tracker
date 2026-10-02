-- GetGrant трекер: обновление 8 — студент сам выбирает вузы из каталога, указывает тип подачи и пишет заметки.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- Сначала должны быть выполнены 005 и 007.
-- Студент по-прежнему НЕ читает таблицы напрямую: только функции ниже, и только свои заявки.
-- Каталог студенту отдаётся без служебных полей кураторов (notes, source).

alter table public.tracker_universities add column if not exists intl_portal text;   -- портал подачи для иностранных студентов
alter table public.tracker_applications add column if not exists added_by text;       -- 'student', если вуз добавил сам студент
alter table public.tracker_applications add column if not exists student_note text;   -- заметки студента (видит куратор)

-- Каталог для выбора вузов студентом (только «публичные» поля).
create or replace function public.student_catalog() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if public.tracker_my_student_id() is null then return null; end if;
  return coalesce((select json_agg(json_build_object(
      'id', u.id, 'name', u.name, 'country', u.country, 'city', u.city, 'rating', u.rating,
      'link', u.link, 'intl_portal', u.intl_portal, 'majors', u.majors, 'language', u.language,
      'deadlines', u.deadlines, 'deadline_text', u.deadline_text, 'reqs', u.reqs, 'aid', u.aid,
      'tuition_usd_min', u.tuition_usd_min, 'tuition_usd_max', u.tuition_usd_max, 'coa_usd', u.coa_usd, 'app_fee_usd', u.app_fee_usd,
      'costs_note', u.costs_note, 'ielts_min', u.ielts_min, 'toefl_min', u.toefl_min, 'duolingo_min', u.duolingo_min,
      'sat_policy', u.sat_policy, 'sat_range', u.sat_range, 'entrance_exam', u.entrance_exam,
      'merit', u.merit, 'full_ride', u.full_ride, 'platform', u.platform, 'verified_intake', u.verified_intake)
    order by u.country, u.name) from public.tracker_universities u), '[]'::json);
end $$;

-- Личный кабинет: как в 005 + id вуза, кто добавил, заметка студента, портал для иностранцев, стоимость и IELTS из каталога.
create or replace function public.student_portal() returns json
language plpgsql stable security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then return null; end if;
  return json_build_object(
    'student', (select json_build_object('name', s.name, 'intake', s.intake, 'major', s.major, 'curator', s.curator, 'targets', s.targets)
                from public.tracker_students s where s.id = sid),
    'apps', coalesce((select json_agg(json_build_object(
        'id', a.id, 'uni_id', a.uni_id, 'uni', u.name, 'country', u.country, 'round', a.round, 'status', a.status, 'program', a.program,
        'grp', a.grp, 'tier', a.tier, 'sort', a.sort, 'added_by', a.added_by, 'student_note', a.student_note,
        'rating', coalesce(a.rating, u.rating), 'sat_range', coalesce(a.sat_range, u.sat_range), 'reqs', coalesce(a.reqs, u.reqs),
        'deadline', coalesce(a.deadline_override::text, u.deadlines ->> a.round), 'deadlines', u.deadlines,
        'deadline_text', coalesce(a.deadline_text, u.deadline_text), 'link', u.link, 'intl_portal', u.intl_portal,
        'tuition_usd_min', u.tuition_usd_min, 'tuition_usd_max', u.tuition_usd_max, 'ielts_min', u.ielts_min)
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

-- Типы подачи — те же, что ROUNDS в index.html и student.html.
create or replace function public.tracker_valid_round(r text) returns boolean
language sql immutable as $$
  select r is null or r in ('ED','ED2','EA','REA','RD','Rolling','UCAS','Стипендия','Другое')
$$;

-- Студент добавляет вуз из каталога в свой список.
create or replace function public.student_add_app(p_uni_id text, p_round text default null, p_program text default null) returns text
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id(); new_id text;
begin
  if sid is null then raise exception 'not a student'; end if;
  if not exists (select 1 from public.tracker_universities where id = p_uni_id) then raise exception 'no such university'; end if;
  p_round := nullif(trim(p_round), '');
  if not public.tracker_valid_round(p_round) then raise exception 'bad round'; end if;
  if exists (select 1 from public.tracker_applications where student_id = sid and uni_id = p_uni_id) then
    raise exception 'already in list' using errcode = '23505';
  end if;
  insert into public.tracker_applications (student_id, uni_id, round, program, status, added_by)
  values (sid, p_uni_id, p_round, left(nullif(trim(p_program), ''), 200), 'Планируем', 'student')
  returning id into new_id;
  return new_id;
end $$;

-- Тип подачи и программу студент меняет только у вузов, которые добавил сам (у вузов от куратора — решает куратор).
create or replace function public.student_update_app(p_app_id text, p_round text, p_program text) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then raise exception 'not a student'; end if;
  p_round := nullif(trim(p_round), '');
  if not public.tracker_valid_round(p_round) then raise exception 'bad round'; end if;
  update public.tracker_applications set round = p_round, program = left(nullif(trim(p_program), ''), 200), updated_at = now()
  where id = p_app_id and student_id = sid and added_by = 'student';
  if not found then raise exception 'not found'; end if;
end $$;

-- Заметка студента — к любому своему вузу.
create or replace function public.student_set_app_note(p_app_id text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then raise exception 'not a student'; end if;
  update public.tracker_applications set student_note = left(nullif(trim(p_note), ''), 4000), updated_at = now()
  where id = p_app_id and student_id = sid;
  if not found then raise exception 'not found'; end if;
end $$;

-- Убрать из списка студент может только вуз, который добавил сам.
create or replace function public.student_remove_app(p_app_id text) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then raise exception 'not a student'; end if;
  delete from public.tracker_applications where id = p_app_id and student_id = sid and added_by = 'student';
  if not found then raise exception 'not found'; end if;
end $$;

revoke all on function public.student_catalog() from public, anon;
revoke all on function public.student_portal() from public, anon;
revoke all on function public.student_add_app(text, text, text) from public, anon;
revoke all on function public.student_update_app(text, text, text) from public, anon;
revoke all on function public.student_set_app_note(text, text) from public, anon;
revoke all on function public.student_remove_app(text) from public, anon;
grant execute on function public.student_catalog() to authenticated;
grant execute on function public.student_portal() to authenticated;
grant execute on function public.student_add_app(text, text, text) to authenticated;
grant execute on function public.student_update_app(text, text, text) to authenticated;
grant execute on function public.student_set_app_note(text, text) to authenticated;
grant execute on function public.student_remove_app(text) to authenticated;
