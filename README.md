# GetGrant — трекер студентов

- `index.html` — трекер кураторов, `student.html` — кабинет студента (оба открываются с главного адреса сайта).
- Данные хранятся в Supabase, сайт публикуется через GitHub Pages.
- `supabase/migrations/` — структура базы (без данных студентов). Новые изменения базы — новым файлом по порядку.
- `AGENTS.md` — описание проекта для Codex / ИИ-помощников.

Важно: в репозиторий не загружаются файлы с данными студентов и секретный ключ `service_role`.

## Документы студентов (Google Диск)
- Файлы хранятся на Google Диске центра, в папке студента. Кураторы и студенты работают с ними только в трекере (вкладка «Документы»).
- `supabase/functions/drive/index.ts` — серверная функция, которая ходит в Google Диск. Ставится в Supabase → Edge Functions, имя `drive`.
- `supabase/migrations/006_drive_documents.sql` — запустить в SQL Editor до публикации.
- Секреты Google (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`, `DRIVE_ROOT_FOLDER_ID`) хранятся только в Supabase → Edge Functions → Secrets, никогда в репозитории.
