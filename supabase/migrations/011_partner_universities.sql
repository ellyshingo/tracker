-- GetGrant трекер: обновление 11 — партнёрские вузы.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- Новое поле «Партнёр GetGrant» у вуза: через кого работаем и приоритет («★ Через Navitas», «Прямой договор», «Не продвигаем»…).
-- Поле только для кураторов: функция student_catalog() его не отдаёт, студенты его не видят.

alter table public.tracker_universities add column if not exists partner text;
