-- GetGrant трекер: обновление 12 — типы студентов.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- Было одно поле «Тип»: Курсы / Поступление / Курсы + Поступление.
-- Стало два поля:
--   • «Когда поступает» (столбец type): «В этом году» / «Позже» —
--     проставляется по сезону поступления: Осень 2027 и Весна 2027 → «В этом году», 2028 и позже → «Позже»;
--     если сезон не определён — поле остаётся пустым;
--   • «Тип поступления» (новый столбец track): «На грант» / «Партнёрские вузы» — заполняют кураторы.

alter table public.tracker_students add column if not exists track text;

update public.tracker_students
set type = case
      when intake in ('Осень 2027', 'Весна 2027') then 'В этом году'
      when intake ~ '20(2[89]|[3-9]\d)' then 'Позже'
      else null end,
    updated_at = now()
where type is null or type not in ('В этом году', 'Позже');
