-- GetGrant трекер: обновление 6 — документы студентов на Google Диске.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- Сами файлы лежат на Google Диске центра; в базе хранится только id папки студента.

alter table public.tracker_students add column if not exists drive_folder_id text;

-- Кто спрашивает и к какой папке ему можно. Куратор — к любому студенту, студент — только к себе.
create or replace function public.drive_access(sid text default null) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  is_staff boolean := public.tracker_is_staff();
  me text := public.tracker_my_student_id();
  r record;
begin
  if not is_staff then
    if me is null or (sid is not null and sid <> me) then return null; end if;
    sid := me;
  end if;
  if sid is null then return null; end if;
  select id, name, drive_folder_id into r from public.tracker_students where id = sid;
  if not found then return null; end if;
  return json_build_object(
    'role', case when is_staff then 'staff' else 'student' end,
    'id', r.id, 'name', r.name, 'folderId', r.drive_folder_id,
    'email', lower(auth.jwt() ->> 'email'));
end $$;

-- Привязать/отвязать папку может только куратор.
create or replace function public.drive_set_folder(sid text, fid text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.tracker_is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.tracker_students set drive_folder_id = nullif(fid, ''), updated_at = now() where id = sid;
end $$;

revoke all on function public.drive_access(text) from public, anon;
revoke all on function public.drive_set_folder(text, text) from public, anon;
grant execute on function public.drive_access(text) to authenticated;
grant execute on function public.drive_set_folder(text, text) to authenticated;
