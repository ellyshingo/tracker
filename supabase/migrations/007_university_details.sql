-- GetGrant трекер: обновление 7 — подробный каталог вузов (деньги в USD, требования числами, подача, актуальность).
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Повторный запуск безопасен.
-- Только новые столбцы; существующие данные не меняются.

alter table public.tracker_universities
  add column if not exists city text,
  add column if not exists uni_type text,            -- Университет / Liberal arts college / Технический…
  add column if not exists ownership text,           -- Частный / Государственный
  add column if not exists language text,            -- язык обучения
  add column if not exists majors text,              -- направления / программы на английском
  add column if not exists tuition_usd_min integer,  -- обучение в год, USD (нижняя граница)
  add column if not exists tuition_usd_max integer,  -- обучение в год, USD (верхняя граница, если диапазон)
  add column if not exists coa_usd integer,          -- полная стоимость года (обучение + жильё + жизнь), USD
  add column if not exists app_fee_usd integer,      -- сбор за подачу, USD
  add column if not exists costs_note text,          -- расходы в исходной валюте, как на сайте вуза
  add column if not exists aid_policy text,          -- Need-blind / Need-aware / Нет need-based помощи
  add column if not exists meets_need text,          -- Да / Нет / Неизвестно
  add column if not exists merit text,               -- мерит-стипендии: Да / Нет / Неизвестно
  add column if not exists full_ride text,           -- полная стипендия: Да / Нет / Неизвестно
  add column if not exists ielts_min numeric(3,1),
  add column if not exists toefl_min integer,
  add column if not exists duolingo_min integer,
  add column if not exists sat_policy text,          -- Обязателен / По желанию / Не рассматривается
  add column if not exists sat_range text,           -- средний SAT принятых, текстом
  add column if not exists entrance_exam text,       -- CSCA / свой экзамен / не нужен
  add column if not exists admit_rate numeric(5,2),  -- % принятых (12 = 12%)
  add column if not exists admit_rate_intl numeric(5,2),
  add column if not exists platform text,            -- Common App / UCAS / Свой портал…
  add column if not exists fee_waiver text,
  add column if not exists css_profile text,
  add column if not exists recs integer,             -- сколько рекомендаций
  add column if not exists supp_essays integer,      -- сколько доп. эссе
  add column if not exists interview text,
  add column if not exists aid_deadline date,        -- дедлайн фин. помощи / стипендии
  add column if not exists verified_intake text,     -- для какого набора проверены данные (2026, 2027…)
  add column if not exists verified_at date,
  add column if not exists source text;              -- откуда данные (ссылки, «от поступивших студентов»)
