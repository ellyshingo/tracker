-- 003: гибкие таблицы вузов в отчёте (группы, порядок, переопределения полей) + расширение каталога вузов.
-- Supabase → SQL Editor → New query → вставить весь файл → Run. Сначала должен быть выполнен update_02.sql. Повторный запуск безопасен.

alter table public.tracker_applications add column if not exists grp text;
alter table public.tracker_applications add column if not exists sort integer;
alter table public.tracker_applications add column if not exists rating text;
alter table public.tracker_applications add column if not exists sat_range text;
alter table public.tracker_applications add column if not exists reqs text;
alter table public.tracker_applications add column if not exists deadline_text text;
alter table public.tracker_applications add column if not exists aid text;
alter table public.tracker_students add column if not exists report_opts jsonb not null default '{}'::jsonb;
alter table public.tracker_students add column if not exists group_notes jsonb not null default '{}'::jsonb;

insert into public.tracker_universities (id, name, country, rating, reqs, deadline_text, aid, deadlines) values
('james-cook-singapore', 'James Cook University Singapore', 'Сингапур', null, 'IELTS 6.0 (без AP и SAT — австралийский филиал)', 'Март–апрель 2027', null, '{}'::jsonb),
('fudan', 'Fudan University', 'Китай', 'QS 30', 'IELTS 6.5–7.0, SAT 1450+ или CSCA 90+, GPA 90%+', 'Февраль 2027', null, '{}'::jsonb),
('tongji', 'Tongji University', 'Китай', 'QS 192', 'IELTS 6.5+, CSCA (Math & Physics) 90+, GPA 85%+', 'Февраль 2027', null, '{}'::jsonb),
('wittenborg', 'Wittenborg University of Applied Sciences', 'Нидерланды', null, 'IELTS 6.5, GPA 85%+', 'Февраль 2027', null, '{}'::jsonb),
('wollongong-malaysia', 'University of Wollongong Malaysia', 'Малайзия', null, 'IELTS 6.0+, GPA 75%+', 'Март–апрель 2027', null, '{}'::jsonb),
('birmingham', 'University of Birmingham', 'Великобритания', 'QS 68', 'IELTS 6.5, GPA 85%+', 'Январь 2027', null, '{}'::jsonb),
('nottingham', 'University of Nottingham', 'Великобритания', 'QS 97', 'IELTS 6.5, GPA 85%+', 'Январь 2027', null, '{}'::jsonb),
('qmul', 'Queen Mary University of London', 'Великобритания', 'QS 103', 'IELTS 6.5, GPA 85%+', 'Январь 2027', null, '{}'::jsonb),
('skku', 'Sungkyunkwan University (SKKU)', 'Южная Корея', 'QS 159', 'IELTS 6.5+, GPA 85%+, SAT 1350+ желательно', 'Март–апрель 2027', null, '{}'::jsonb),
('kangwon', 'Kangwon National University', 'Южная Корея', null, 'IELTS 6.5+, GPA 85%+, SAT желательно', 'Март–апрель 2027', null, '{}'::jsonb),
('upenn', 'University of Pennsylvania (UPenn)', 'США', 'QS 11', null, 'ED: 1 нояб. / RD: 5 янв.', 'Need-aware, 100% Need met. Ivy League, сильнейший Data/Business профиль.', '{"ED": "2026-11-01", "RD": "2027-01-05"}'::jsonb),
('jhu', 'Johns Hopkins University (JHU)', 'США', 'QS 32', null, 'ED: 1 нояб. / RD: 2 янв.', 'Need-aware, 100% Need met. Сильнейшая научная база.', '{"ED": "2026-11-01", "RD": "2027-01-02"}'::jsonb),
('williams', 'Williams College', 'США', 'LAC #1', null, 'ED: 15 нояб. / RD: 8 янв.', 'Need-blind + Full Need. Топ-1 Liberal Arts College в США.', '{"ED": "2026-11-15", "RD": "2027-01-08"}'::jsonb),
('rice', 'Rice University', 'США', 'QS 120', null, 'ED: 1 нояб. / RD: 4 янв.', 'Need-aware, 100% Need met. Отличный STEM центр в Техасе.', '{"ED": "2026-11-01", "RD": "2027-01-04"}'::jsonb),
('georgetown', 'Georgetown University', 'США', 'QS 301', null, 'EA: 1 нояб. / RD: 10 янв.', 'Need-aware. Ограниченное количество грантов для иностранцев.', '{"EA": "2026-11-01", "RD": "2027-01-10"}'::jsonb),
('boston-university', 'Boston University', 'США', 'QS 108', null, 'ED: 1 нояб. / RD: 4 янв.', 'Trustee / Presidential Scholarships. Мерит-стипендии при подаче до 1 декабря.', '{"ED": "2026-11-01", "RD": "2027-01-04"}'::jsonb),
('northeastern', 'Northeastern University', 'США', 'QS 396', null, 'EA: 1 нояб. / RD: 1 янв.', 'Мерит-стипендии + Сильная Co-op программа (оплачиваемые стажировки).', '{"EA": "2026-11-01", "RD": "2027-01-01"}'::jsonb),
('lafayette', 'Lafayette College', 'США', 'LAC #30', null, 'ED: 15 нояб. / RD: 15 янв.', 'Need-aware + Marquis Scholarships. Сильная инженерия и Data Science.', '{"ED": "2026-11-15", "RD": "2027-01-15"}'::jsonb),
('lehigh', 'Lehigh University', 'США', 'QS 521', null, 'ED: 1 нояб. / RD: 1 янв.', 'Need-based aid & Merit. Сильный уклон в бизнес и аналитику.', '{"ED": "2026-11-01", "RD": "2027-01-01"}'::jsonb),
('umiami', 'University of Miami', 'США', 'QS 561', null, 'EA: 1 нояб. / RD: 1 янв.', 'Stamps / Presidential Scholarships. Полные мерит-стипендии.', '{"EA": "2026-11-01", "RD": "2027-01-01"}'::jsonb),
('cityu', 'CityU (City University of Hong Kong)', 'Гонконг', 'QS 52', null, 'Early Round: 15 ноября 2026
Main Round: 15 января 2027', 'Top Scholarship / Full Tuition Scholarship: Полное покрытие обучения + стипендия на проживание (до 180,000 HKD/год).', '{}'::jsonb),
('hkust-gz', 'HKUST Guangzhou', 'Китай', null, null, 'Early Round: 15 декабря / Main Round: 31 марта.', 'Guangzhou/University International Scholarship: Полное покрытие обучения + льготное проживание + ежемесячная стипендия на личные расходы.', '{}'::jsonb),
('cityu-columbia', 'CityU & Columbia University (Dual Degree)', 'Гонконг', null, null, 'Подача в CityU: До 15 ноября 2026 (Early) или 15 января 2027 (Main).
Подача на саму Dual Degree: Происходит на 2-м курсе обучения в CityU (ноябрь 2028 года) при условии поддержания GPA выше 3.66/4.0.', 'Первые 2 года (CityU): Покрывается стандартными стипендиями CityU.
3 и 4 курс (Columbia GS): Финансовая помощь от Columbia University для международных студентов по этой программе очень ограничена. Студенты оплачивают обучение Columbia по стандартной стоимости per-credit (стоимость года ~$80,000–90,000+ без учёта мерит-грантов).', '{}'::jsonb),
('utoronto', 'University of Toronto', 'Канада', 'QS 25', null, '15 января', 'Академический Safe. Стипендия Lester B. Pearson (1 слот на школу, крайняя конкуренция).', '{}'::jsonb),
('ubc', 'UBC (University of British Columbia)', 'Канада', 'QS 38', null, '15 января', 'Karen McKellin International Leader Award (нужно отдельное выдвижение).', '{}'::jsonb),
('mcgill', 'McGill University', 'Канада', 'QS 29', null, '15 января', 'Зачисление строго по оценкам. Финансовая помощь иностранцам минимальна.', '{}'::jsonb),
('waterloo', 'University of Waterloo', 'Канада', 'QS 115', null, '1 февраля', 'Топ-1 в Канаде по Computer Science/Data. Только небольшие мерит-стипендии ($2k–5k).', '{}'::jsonb)
on conflict (id) do nothing;
