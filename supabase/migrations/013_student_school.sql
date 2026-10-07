-- GetGrant трекер: обновление 13 — где учится студент (центр или школа-партнёр).
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- «Где учится»: Центр GetGrant / Келечек MIT / Звёздочка. Все уже внесённые студенты — «Центр GetGrant».

alter table public.tracker_students add column if not exists school text;
update public.tracker_students set school = 'Центр GetGrant', updated_at = now() where coalesce(school, '') = '';
