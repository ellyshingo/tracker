-- GetGrant трекер: обновление 10 — студенты сами добавляют и редактируют вузы в общем каталоге.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен. Сначала должны быть выполнены 007–009.
-- Как работает:
--   • правка студента сразу видна всем студентам в каталоге;
--   • каждое изменение записывается в историю (кто, когда, было → стало); куратор видит пометку «изменено студентом»
--     и одной кнопкой возвращает прежнее значение;
--   • студенты НЕ меняют поля отчёта (требования текстом, финансовая поддержка, рейтинг, дедлайны текстом)
--     и не видят служебные поля кураторов (заметки, источник, история правок);
--   • студенты НЕ читают таблицы напрямую — только функции ниже.

alter table public.tracker_universities
  add column if not exists community_notes text,                 -- «Полезное от студентов»: гранты, требования, советы
  add column if not exists created_by_student text,              -- id студента, если вуз добавил студент
  add column if not exists last_student_edit_at timestamptz,     -- когда студент последний раз что-то менял
  add column if not exists student_edits_reviewed_at timestamptz; -- когда куратор отметил правки как проверенные

create table if not exists public.tracker_uni_changes (
  id text primary key default gen_random_uuid()::text,
  uni_id text not null references public.tracker_universities(id) on delete cascade,
  field text not null,
  old_value text,
  new_value text,
  student_id text references public.tracker_students(id) on delete set null,
  student_name text,
  created_at timestamptz not null default now(),
  reverted_at timestamptz,
  reverted_by text,
  updated_at timestamptz not null default now()
);
create index if not exists tracker_uni_changes_uni on public.tracker_uni_changes (uni_id, created_at desc);
alter table public.tracker_uni_changes enable row level security;
drop policy if exists "staff full access" on public.tracker_uni_changes;
create policy "staff full access" on public.tracker_uni_changes for all to authenticated
  using (public.tracker_is_staff()) with check (public.tracker_is_staff());

-- Поля, которые может менять студент: [столбец, тип]. Типы: text, url, int, dec (IELTS), date, list:вариант|вариант.
create or replace function public.tracker_student_uni_fields() returns table (col text, typ text)
language sql immutable as $$
  values ('link','url'), ('intl_portal','url'),
         ('tuition_usd_min','int'), ('tuition_usd_max','int'), ('coa_usd','int'), ('app_fee_usd','int'), ('costs_note','text'),
         ('ielts_min','dec'), ('toefl_min','int'), ('duolingo_min','int'),
         ('sat_policy','list:Обязателен|По желанию|Не рассматривается|Неизвестно'), ('sat_range','text'), ('entrance_exam','text'),
         ('majors','text'), ('merit','list:Да|Нет|Неизвестно'), ('full_ride','list:Да|Нет|Неизвестно'),
         ('aid_deadline','date'), ('platform','list:Common App|UCAS|Coalition|Свой портал|Другое'), ('community_notes','text')
$$;

-- Сохранить вуз: p_uni_id = null — новый вуз (нужны name и country), иначе — правка существующего.
-- p_data — JSON с полями из списка выше + deadlines {"Early":"YYYY-MM-DD","Regular":…,"Rolling":…};
-- name/country можно менять только у вуза, который добавил сам этот студент. Возвращает id вуза.
create or replace function public.student_save_uni(p_uni_id text, p_data jsonb, p_add_to_list boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare
  sid text := public.tracker_my_student_id(); sname text; uid text := p_uni_id; f record; raw text; old text;
  pgt text; changed boolean; nd jsonb; od jsonb; k text; own boolean; n int := 0;
begin
  if sid is null then raise exception 'not a student'; end if;
  select name into sname from public.tracker_students where id = sid;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'bad data'; end if;

  if uid is null then  -- новый вуз
    raw := left(nullif(trim(p_data->>'name'), ''), 200);
    if raw is null or nullif(trim(p_data->>'country'), '') is null then raise exception 'name and country required'; end if;
    if exists (select 1 from public.tracker_universities where lower(trim(name)) = lower(raw)) then
      raise exception 'university exists' using errcode = '23505';
    end if;
    insert into public.tracker_universities (name, country, created_by_student, last_student_edit_at)
    values (raw, left(trim(p_data->>'country'), 60), sid, now()) returning id into uid;
    insert into public.tracker_uni_changes (uni_id, field, old_value, new_value, student_id, student_name)
    values (uid, 'создан вуз', null, raw || ' · ' || trim(p_data->>'country'), sid, sname);
  else
    if not exists (select 1 from public.tracker_universities where id = uid) then raise exception 'no such university'; end if;
    select created_by_student = sid into own from public.tracker_universities where id = uid;
    -- название и страна — только у своего вуза
    foreach k in array array['name','country'] loop
      if p_data ? k then
        raw := left(nullif(trim(p_data->>k), ''), case when k = 'name' then 200 else 60 end);
        execute format('select %I from public.tracker_universities where id = $1', k) into old using uid;
        if raw is distinct from old then
          if not coalesce(own, false) then raise exception 'only own university: %', k; end if;
          if raw is null then raise exception '% required', k; end if;
          execute format('update public.tracker_universities set %I = $1 where id = $2', k) using raw, uid;
          insert into public.tracker_uni_changes (uni_id, field, old_value, new_value, student_id, student_name) values (uid, k, old, raw, sid, sname);
          n := n + 1;
        end if;
      end if;
    end loop;
  end if;

  for f in select * from public.tracker_student_uni_fields() loop
    if not (p_data ? f.col) then continue; end if;
    raw := nullif(trim(p_data->>f.col), '');
    if raw is not null then
      if length(raw) > 3000 then raise exception 'too long: %', f.col; end if;
      if f.typ = 'url' and raw !~* '^https?://\S+$' then raise exception 'bad url: %', f.col; end if;
      if f.typ = 'int' and raw !~ '^\d{1,7}$' then raise exception 'bad number: %', f.col; end if;
      if f.typ = 'dec' and (raw !~ '^\d(\.\d)?$' or raw::numeric > 9) then raise exception 'bad ielts: %', f.col; end if;
      if f.typ = 'date' and (raw !~ '^\d{4}-\d{2}-\d{2}$' or raw::date is null) then raise exception 'bad date: %', f.col; end if;
      if f.typ like 'list:%' and not (raw = any(string_to_array(substr(f.typ, 6), '|'))) then raise exception 'bad value: %', f.col; end if;
    end if;
    execute format('select %I::text from public.tracker_universities where id = $1', f.col) into old using uid;
    changed := case when f.typ in ('int','dec') then (raw::numeric) is distinct from (old::numeric) else raw is distinct from old end;
    if changed then
      pgt := case f.typ when 'int' then 'integer' when 'dec' then 'numeric' when 'date' then 'date' else 'text' end;
      execute format('update public.tracker_universities set %I = $1::%s where id = $2', f.col, pgt) using raw, uid;
      insert into public.tracker_uni_changes (uni_id, field, old_value, new_value, student_id, student_name) values (uid, f.col, old, raw, sid, sname);
      n := n + 1;
    end if;
  end loop;

  if p_data ? 'deadlines' then  -- только Early / Regular / Rolling
    if jsonb_typeof(p_data->'deadlines') <> 'object' then raise exception 'bad deadlines'; end if;
    nd := '{}'::jsonb;
    foreach k in array array['Early','Regular','Rolling'] loop
      raw := nullif(trim(p_data->'deadlines'->>k), '');
      if raw is not null then
        if raw !~ '^\d{4}-\d{2}-\d{2}$' or raw::date is null then raise exception 'bad date: %', k; end if;
        nd := nd || jsonb_build_object(k, raw);
      end if;
    end loop;
    select coalesce(deadlines, '{}'::jsonb) into od from public.tracker_universities where id = uid;
    if nd is distinct from od then
      update public.tracker_universities set deadlines = nd where id = uid;
      insert into public.tracker_uni_changes (uni_id, field, old_value, new_value, student_id, student_name) values (uid, 'deadlines', od::text, nd::text, sid, sname);
      n := n + 1;
    end if;
  end if;

  if n > 0 then update public.tracker_universities set last_student_edit_at = now(), updated_at = now() where id = uid; end if;
  if p_add_to_list and not exists (select 1 from public.tracker_applications where student_id = sid and uni_id = uid) then
    insert into public.tracker_applications (student_id, uni_id, status, added_by) values (sid, uid, 'Планируем', 'student');
  end if;
  return uid;
end $$;

-- Каталог для студентов: как в 008 + «Полезное от студентов» и дата последней правки студентом (без имён).
create or replace function public.student_catalog() returns json
language plpgsql stable security definer set search_path = public as $$
declare sid text := public.tracker_my_student_id();
begin
  if sid is null then return null; end if;
  return coalesce((select json_agg(json_build_object(
      'id', u.id, 'name', u.name, 'country', u.country, 'city', u.city, 'rating', u.rating,
      'link', u.link, 'intl_portal', u.intl_portal, 'majors', u.majors, 'language', u.language,
      'deadlines', u.deadlines, 'deadline_text', u.deadline_text, 'reqs', u.reqs, 'aid', u.aid,
      'tuition_usd_min', u.tuition_usd_min, 'tuition_usd_max', u.tuition_usd_max, 'coa_usd', u.coa_usd, 'app_fee_usd', u.app_fee_usd,
      'costs_note', u.costs_note, 'ielts_min', u.ielts_min, 'toefl_min', u.toefl_min, 'duolingo_min', u.duolingo_min,
      'sat_policy', u.sat_policy, 'sat_range', u.sat_range, 'entrance_exam', u.entrance_exam,
      'merit', u.merit, 'full_ride', u.full_ride, 'platform', u.platform, 'aid_deadline', u.aid_deadline,
      'verified_intake', u.verified_intake, 'community_notes', u.community_notes,
      'student_edited_at', u.last_student_edit_at, 'mine', coalesce(u.created_by_student = sid, false))
    order by u.country, u.name) from public.tracker_universities u), '[]'::json);
end $$;

revoke all on function public.student_save_uni(text, jsonb, boolean) from public, anon;
revoke all on function public.student_catalog() from public, anon;
revoke all on function public.tracker_student_uni_fields() from public, anon;
grant execute on function public.student_save_uni(text, jsonb, boolean) to authenticated;
grant execute on function public.student_catalog() to authenticated;
