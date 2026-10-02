// GetGrant трекер — функция «drive»: документы студентов на Google Диске центра.
// Кураторы и студенты работают только в трекере; файлы физически лежат на Диске
// аккаунта центра. Студенты к Диску доступа не имеют — всё идёт через эту функцию.
//
// Секреты (Supabase → Edge Functions → Secrets):
//   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN, DRIVE_ROOT_FOLDER_ID
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY Supabase добавляет сам.
//
// Кто что может:
//   куратор — всё: создать/привязать папку, загрузить, скачать, показать/скрыть от студента, удалить, удалить всё;
//   студент — только своя папка: видит файлы, отмеченные «видно студенту», загружает,
//             удаляет только то, что загрузил сам. Рекомендательные письма и т.п. куратор просто не открывает студенту.

const MAX_BYTES = 25 * 1024 * 1024;
const FOLDER = "application/vnd.google-apps.folder";
const FILE_FIELDS = "id,name,mimeType,size,modifiedTime,appProperties,webViewLink,parents,trashed";
const env = (k) => Deno.env.get(k) || "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Expose-Headers": "content-disposition, x-file-name",
};
const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" } });
class HttpError extends Error { constructor(status, msg) { super(msg); this.status = status; } }
const deny = (msg = "Нет доступа") => { throw new HttpError(403, msg); };

/* ---------- Google ---------- */
let token = { value: "", exp: 0 };
async function gToken() {
  if (token.value && Date.now() < token.exp - 60_000) return token.value;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("GOOGLE_CLIENT_ID"), client_secret: env("GOOGLE_CLIENT_SECRET"),
      refresh_token: env("GOOGLE_REFRESH_TOKEN"), grant_type: "refresh_token",
    }),
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || !d.access_token) {
    console.error("google token", r.status, d);
    throw new HttpError(502, d.error === "invalid_grant"
      ? "Google отозвал доступ (invalid_grant). Получите новый GOOGLE_REFRESH_TOKEN по инструкции, шаг 5."
      : "Не удалось подключиться к Google Диску. Проверьте секреты GOOGLE_* в Supabase.");
  }
  token = { value: d.access_token, exp: Date.now() + (d.expires_in || 3600) * 1000 };
  return token.value;
}
async function g(path, init = {}, raw = false) {
  const base = path.startsWith("http") ? path : "https://www.googleapis.com/drive/v3/" + path;
  const url = base + (base.includes("?") ? "&" : "?") + "supportsAllDrives=true";
  const r = await fetch(url, { ...init, headers: { ...(init.headers || {}), Authorization: "Bearer " + (await gToken()) } });
  if (raw) { if (!r.ok) throw new HttpError(r.status === 404 ? 404 : 502, "Файл не найден на Диске"); return r; }
  const d = await r.json().catch(() => ({}));
  if (!r.ok) {
    console.error("drive", path, r.status, JSON.stringify(d));
    if (r.status === 404) throw new HttpError(404, "Не найдено на Диске (возможно, удалено или нет доступа у аккаунта центра)");
    throw new HttpError(502, "Ошибка Google Диска: " + (d.error && d.error.message || r.status));
  }
  return d;
}
const getFile = (id) => g("files/" + encodeURIComponent(id) + "?fields=" + FILE_FIELDS);
async function listChildren(folderId) {
  const out = []; let page = "";
  do {
    const q = encodeURIComponent(`'${folderId.replace(/'/g, "")}' in parents and trashed=false`);
    const d = await g(`files?q=${q}&fields=nextPageToken,files(${FILE_FIELDS})&pageSize=200&orderBy=folder,name&includeItemsFromAllDrives=true` + (page ? "&pageToken=" + page : ""));
    out.push(...(d.files || [])); page = d.nextPageToken || "";
  } while (page && out.length < 1000);
  return out;
}
// Все файлы папки студента, включая подпапки (до 3 уровней) — старые папки часто разложены по подпапкам.
async function listTree(rootId) {
  const files = []; const queue = [{ id: rootId, path: "", depth: 0 }];
  while (queue.length && files.length < 500) {
    const f = queue.shift();
    for (const it of await listChildren(f.id)) {
      if (it.mimeType === FOLDER) { if (f.depth < 3) queue.push({ id: it.id, path: f.path + it.name + " / ", depth: f.depth + 1 }); }
      else files.push({ ...it, path: f.path });
    }
  }
  return files;
}
// Файл должен лежать внутри папки студента — иначе по чужому id можно было бы скачать что угодно.
async function insideFolder(file, rootId) {
  let parents = file.parents || [];
  for (let depth = 0; depth < 5 && parents.length; depth++) {
    if (parents.includes(rootId)) return true;
    const p = await getFile(parents[0]).catch(() => null);
    parents = (p && p.parents) || [];
  }
  return false;
}
async function createFolder(name, parent) {
  return g("files?fields=id,webViewLink", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, mimeType: FOLDER, parents: [parent] }),
  });
}
async function uploadFile(folderId, file, meta) {
  const boundary = "gg" + crypto.randomUUID().replace(/-/g, "");
  const metadata = { name: meta.name, parents: [folderId], appProperties: meta.props, description: meta.description || "" };
  const body = new Blob([
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n`,
    `--${boundary}\r\nContent-Type: ${file.type || "application/octet-stream"}\r\n\r\n`,
    new Uint8Array(await file.arrayBuffer()),
    `\r\n--${boundary}--`,
  ]);
  return g("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=" + FILE_FIELDS, {
    method: "POST", headers: { "Content-Type": "multipart/related; boundary=" + boundary }, body,
  });
}
const folderUrl = (id) => id ? "https://drive.google.com/drive/folders/" + id : "";
const parseFolderId = (s) => {
  s = String(s || "").trim();
  const m = s.match(/\/folders\/([\w-]{10,})/) || s.match(/[?&]id=([\w-]{10,})/) || s.match(/^([\w-]{10,})$/);
  return m ? m[1] : "";
};

/* ---------- Supabase (права проверяет база, а не браузер) ---------- */
async function rpc(fn, args, auth) {
  const r = await fetch(env("SUPABASE_URL") + "/rest/v1/rpc/" + fn, {
    method: "POST",
    headers: { apikey: env("SUPABASE_ANON_KEY"), Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  const d = await r.json().catch(() => null);
  if (!r.ok) { console.error("rpc", fn, r.status, d); throw new HttpError(r.status === 401 ? 401 : 403, (d && d.message) || "Нет доступа"); }
  return d;
}
// Студенту привязать папку может только сама функция (сервисным ключом) — сам студент через базу этого сделать не может.
async function saveFolderAsService(sid, fid) {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) throw new HttpError(500, "Нет SUPABASE_SERVICE_ROLE_KEY");
  const r = await fetch(env("SUPABASE_URL") + "/rest/v1/tracker_students?id=eq." + encodeURIComponent(sid), {
    method: "PATCH",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ drive_folder_id: fid }),
  });
  if (!r.ok) throw new HttpError(500, "Не удалось сохранить папку в базе");
}

const view = (f, staff) => ({
  id: f.id, name: f.name, mimeType: f.mimeType, size: f.size ? Number(f.size) : null, modifiedTime: f.modifiedTime,
  path: f.path || "", category: (f.appProperties || {}).gg_cat || "", visible: (f.appProperties || {}).gg_vis === "1",
  uploadedBy: (f.appProperties || {}).gg_by || "", byStudent: (f.appProperties || {}).gg_src === "student",
  ...(staff ? { link: f.webViewLink || "" } : {}),
});
const studentSees = (f) => (f.appProperties || {}).gg_vis === "1";
const canStudentDelete = (f, email) => (f.appProperties || {}).gg_src === "student" && (f.appProperties || {}).gg_by === email;

async function fileInScope(acc, fileId) {
  if (!acc.folderId) deny("У студента нет папки");
  const f = await getFile(fileId);
  if (f.trashed || f.mimeType === FOLDER || !(await insideFolder(f, acc.folderId))) deny("Файл не из папки этого студента");
  if (acc.role !== "staff" && !studentSees(f)) deny();
  return f;
}

/* ---------- обработчик ---------- */
async function handler(req) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Войдите заново" }, 401);
  try {
    const isForm = (req.headers.get("Content-Type") || "").includes("multipart/form-data");
    const form = isForm ? await req.formData() : null;
    const body = form ? Object.fromEntries([...form.entries()].filter(([, v]) => typeof v === "string")) : await req.json().catch(() => ({}));
    const action = String(body.action || "");
    const acc = await rpc("drive_access", { sid: body.studentId || null }, auth);
    if (!acc) deny("Нет доступа к этому студенту");
    const staff = acc.role === "staff";
    const onlyStaff = () => { if (!staff) deny("Только для кураторов"); };

    if (action === "list") {
      if (!acc.folderId) return json({ role: acc.role, folderId: null, files: [] });
      let files = await listTree(acc.folderId);
      if (!staff) files = files.filter(studentSees);
      return json({ role: acc.role, folderId: acc.folderId, folderUrl: staff ? folderUrl(acc.folderId) : "", files: files.map((f) => view(f, staff)) });
    }

    if (action === "create") {
      onlyStaff();
      if (acc.folderId) return json({ folderId: acc.folderId, folderUrl: folderUrl(acc.folderId) });
      const root = env("DRIVE_ROOT_FOLDER_ID"); if (!root) throw new HttpError(500, "Не задан секрет DRIVE_ROOT_FOLDER_ID");
      const f = await createFolder(acc.name || acc.id, root);
      await rpc("drive_set_folder", { sid: acc.id, fid: f.id }, auth);
      return json({ folderId: f.id, folderUrl: folderUrl(f.id) });
    }

    if (action === "link") {
      onlyStaff();
      const fid = parseFolderId(body.folder);
      if (!fid) throw new HttpError(400, "Не похоже на ссылку на папку Google Диска");
      const f = await getFile(fid);
      if (f.mimeType !== FOLDER) throw new HttpError(400, "Это ссылка на файл, а нужна ссылка на папку");
      await rpc("drive_set_folder", { sid: acc.id, fid }, auth);
      return json({ folderId: fid, folderUrl: folderUrl(fid) });
    }

    if (action === "unlink") {
      onlyStaff();
      await rpc("drive_set_folder", { sid: acc.id, fid: null }, auth);
      return json({ ok: true });
    }

    if (action === "upload") {
      const file = form && form.get("file");
      if (!file || typeof file === "string") throw new HttpError(400, "Нет файла");
      if (file.size > MAX_BYTES) throw new HttpError(413, "Файл больше 25 МБ — сожмите его или загрузите частями");
      let folderId = acc.folderId;
      if (!folderId) {
        const root = env("DRIVE_ROOT_FOLDER_ID"); if (!root) throw new HttpError(500, "Не задан секрет DRIVE_ROOT_FOLDER_ID");
        folderId = (await createFolder(acc.name || acc.id, root)).id;
        if (staff) await rpc("drive_set_folder", { sid: acc.id, fid: folderId }, auth);
        else await saveFolderAsService(acc.id, folderId);
      }
      const cat = String(body.category || "").slice(0, 60);
      const orig = String(file.name || "файл").replace(/[\\/]/g, "_").slice(0, 150);
      const name = cat && cat !== "Другое" && !orig.startsWith(cat) ? `${cat} — ${orig}` : orig;
      const props = { gg_cat: cat, gg_by: acc.email || "", gg_src: staff ? "staff" : "student", gg_vis: staff ? (body.visible === "1" ? "1" : "0") : "1" };
      const f = await uploadFile(folderId, file, { name, props, description: "Загружено через трекер GetGrant: " + (acc.email || "") });
      return json({ file: view(f, staff), folderId });
    }

    if (action === "download") {
      const f = await fileInScope(acc, String(body.fileId || ""));
      const google = f.mimeType.startsWith("application/vnd.google-apps.");
      const r = await g("files/" + encodeURIComponent(f.id) + (google ? "/export?mimeType=application%2Fpdf" : "?alt=media"), {}, true);
      const name = google ? f.name + ".pdf" : f.name;
      return new Response(r.body, { headers: {
        ...CORS, "Content-Type": google ? "application/pdf" : (f.mimeType || "application/octet-stream"),
        "Content-Disposition": "attachment; filename*=UTF-8''" + encodeURIComponent(name), "X-File-Name": encodeURIComponent(name),
      } });
    }

    if (action === "visibility") {
      onlyStaff();
      const f = await fileInScope(acc, String(body.fileId || ""));
      await g("files/" + encodeURIComponent(f.id) + "?fields=id", { method: "PATCH", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ appProperties: { gg_vis: body.visible ? "1" : "0" } }) });
      return json({ ok: true });
    }

    if (action === "category") {
      onlyStaff();
      const f = await fileInScope(acc, String(body.fileId || ""));
      await g("files/" + encodeURIComponent(f.id) + "?fields=id", { method: "PATCH", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ appProperties: { gg_cat: String(body.category || "").slice(0, 60) } }) });
      return json({ ok: true });
    }

    if (action === "delete") {
      const f = await fileInScope(acc, String(body.fileId || ""));
      if (!staff && !canStudentDelete(f, acc.email)) deny("Удалить можно только файлы, которые вы загрузили сами");
      await g("files/" + encodeURIComponent(f.id) + "?fields=id", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ trashed: true }) });
      return json({ ok: true });
    }

    if (action === "purge") {
      onlyStaff();
      if (body.confirm !== "УДАЛИТЬ") throw new HttpError(400, "Нужно подтверждение");
      if (acc.folderId) {
        await g("files/" + encodeURIComponent(acc.folderId) + "?fields=id", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ trashed: true }) });
        await rpc("drive_set_folder", { sid: acc.id, fid: null }, auth);
      }
      return json({ ok: true });
    }

    return json({ error: "Неизвестное действие" }, 400);
  } catch (e) {
    const status = e instanceof HttpError ? e.status : 500;
    if (status === 500) console.error(e);
    return json({ error: e instanceof HttpError ? e.message : "Внутренняя ошибка" }, status);
  }
}

Deno.serve(handler);
