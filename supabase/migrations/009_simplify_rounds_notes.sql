-- GetGrant трекер: обновление 9 — упрощение.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- После этого файла НЕ запускайте заново 008: он вернёт старые типы подачи для личного кабинета (если запустили — просто выполните 009 ещё раз).
-- 1) Типы подачи: вместо ED / ED2 / EA / REA / RD / UCAS / Стипендия / Другое — только Early, Regular, Rolling.
--    ED, ED2, EA, REA → Early (в каталоге — самая ранняя из этих дат); RD, UCAS → Regular; Rolling → Rolling.
--    Отсчёт дней в заявках не сбивается: если у заявки был дедлайн из каталога и после перевода он стал бы другим,
--    старая дата сохраняется в заявке как «свой дедлайн».
--    Дата «Стипендия» из каталога переносится в поле «Дедлайн фин. помощи / стипендии».
-- 2) «Заметки» из профиля студента переносятся в журнал встреч (одна запись «перенесено из профиля»), поле в профиле очищается.

-- 1a. заявки: сохранить точную дату там, где она изменилась бы
update public.tracker_applications a
set deadline_override = (u.deadlines ->> a.round)::date, updated_at = now()
from public.tracker_universities u
where u.id = a.uni_id and a.deadline_override is null
  and a.round in ('ED','ED2','EA','REA','RD','UCAS','Стипендия','Другое')
  and coalesce(u.deadlines ->> a.round, '') <> ''
  and (u.deadlines ->> a.round) is distinct from (case
        when a.round in ('ED','ED2','EA','REA') then least(u.deadlines->>'ED', u.deadlines->>'ED2', u.deadlines->>'EA', u.deadlines->>'REA')
        when a.round in ('RD','UCAS') then coalesce(u.deadlines->>'RD', u.deadlines->>'UCAS')
        else null end);

-- 1b. заявки: новые типы подачи
update public.tracker_applications
set round = case when round in ('ED','ED2','EA','REA') then 'Early' when round in ('RD','UCAS') then 'Regular' when round = 'Rolling' then 'Rolling' else null end,
    updated_at = now()
where round is not null and round not in ('Early','Regular','Rolling');

-- 1c. каталог: даты по новым типам; «Стипендия» → дедлайн фин. помощи
update public.tracker_universities
set aid_deadline = coalesce(aid_deadline, nullif(deadlines->>'Стипендия','')::date),
    deadlines = jsonb_strip_nulls(jsonb_build_object(
      'Early',   nullif(least(deadlines->>'Early', deadlines->>'ED', deadlines->>'ED2', deadlines->>'EA', deadlines->>'REA'), ''),
      'Regular', nullif(coalesce(deadlines->>'Regular', deadlines->>'RD', deadlines->>'UCAS'), ''),
      'Rolling', nullif(deadlines->>'Rolling', ''))),
    updated_at = now()
where deadlines ?| array['ED','ED2','EA','REA','RD','UCAS','Стипендия','Другое'];

-- 1d. студент в личном кабинете может выбрать только новые типы
create or replace function public.tracker_valid_round(r text) returns boolean
language sql immutable as $$
  select r is null or r in ('Early','Regular','Rolling')
$$;

-- 2. заметки профиля → журнал встреч
insert into public.tracker_meetings (student_id, date, author, notes)
select id, coalesce(updated_at::date, current_date), 'перенесено из профиля', trim(notes)
from public.tracker_students where coalesce(trim(notes), '') <> '';
update public.tracker_students set notes = null, updated_at = now() where coalesce(trim(notes), '') <> '';
