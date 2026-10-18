/* ONE · ORT dashboard (ECC-160) — Vue 3 (no build step) + Leaflet + Supabase */
const { createApp, reactive, computed, onMounted, nextTick, watch } = Vue;
const C = window.KOC_CONFIG;
const sb = supabase.createClient(C.SUPABASE_URL, C.SUPABASE_KEY);

// Bilingual constants: every label is { ar, en }; L() picks the current language.
const KINDS = {
  signal1: { label: { ar: "الإشارة 1 · طوارئ", en: "Signal 1 · Emergency" }, short: { ar: "طوارئ", en: "Emergency" }, cls: "k1",
    title: { ar: "الإشارة 1 — طوارئ", en: "Signal 1 — Emergency" },
    body: { ar: "1. ابقَ متأهبًا في مكانك\n2. استمع لتعليمات النداء العام\n3. أوقف الأعمال الخطرة وأمّن المعدات",
            en: "1. Stay alert and ready in place\n2. Listen to public address instructions\n3. Stop hazardous work and secure equipment" } },
  signal2: { label: { ar: "الإشارة 2 · إخلاء", en: "Signal 2 · Evacuate" }, short: { ar: "إخلاء", en: "Evacuation" }, cls: "k2",
    title: { ar: "الإشارة 2 — إخلاء", en: "Signal 2 — Evacuate" },
    body: { ar: "1. أخلِ المنطقة وفق تعليمات النداء العام\n2. استخدم مسارات الإخلاء الآمنة — لا مصاعد\n3. توجّه إلى نقطة التجمع\n4. سجّل حالتك في التطبيق عند الوصول",
            en: "1. Evacuate the area per PA instructions\n2. Use safe evacuation routes — no lifts\n3. Go to the muster point\n4. Record your status in the app on arrival" } },
  signal3: { label: { ar: "الإشارة 3 · زوال الخطر", en: "Signal 3 · All clear" }, short: { ar: "زوال الخطر", en: "All clear" }, cls: "k3",
    title: { ar: "الإشارة 3 — زوال الخطر", en: "Signal 3 — All clear" },
    body: { ar: "1. عُد إلى مكان عملك\n2. اتبع تعليمات مسؤول الإخلاء\n3. أُغلق الحادث وسُجّل",
            en: "1. Return to your workplace\n2. Follow the fire warden’s instructions\n3. The incident is closed and logged" } },
  message: { label: { ar: "رسالة تنبيه", en: "Safety message" }, short: { ar: "تنبيه", en: "Message" }, cls: "km",
    title: { ar: "تنبيه سلامة", en: "Safety alert" }, body: { ar: "", en: "" } },
};
const SCOPES = { employee: { ar: "موظف", en: "Employee" }, building: { ar: "مبنى", en: "Building" }, zone: { ar: "Zone", en: "Zone" },
  sector: { ar: "قطاع", en: "Sector" }, all: { ar: "جميع القطاعات", en: "All sectors" } };
const STATUS = {
  received: [{ ar: "استلم — لم يرد", en: "Received — no reply" }, "st-wait"], safe: [{ ar: "آمن", en: "Safe" }, "st-ok"],
  need_help: [{ ar: "يحتاج مساعدة", en: "Needs help" }, "st-warn"], injured: [{ ar: "مصاب", en: "Injured" }, "st-bad"],
  trapped: [{ ar: "محتجز", en: "Trapped" }, "st-bad"], none: [{ ar: "لم يستلم", en: "Not received" }, "st-none"],
};
const NAV = [
  { k: "map", t: { ar: "الخريطة الحية", en: "Live map" }, tag: { ar: "ECC-160 · كل المواقع", en: "ECC-160 · all sites" }, h: { ar: "صورة واحدة لكل المواقع", en: "One picture of every site" }, i: "M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2zm0 0v14m6-12v14" },
  { k: "alarms", t: { ar: "الإنذارات", en: "Alarms" }, tag: { ar: "الإنذار والحصر", en: "Alarm & muster" }, h: { ar: "إطلاق الإنذار ومتابعة الحصر", en: "Launch alarms and follow the muster" }, i: "M12 3a6 6 0 0 0-6 6v4l-2 3h16l-2-3V9a6 6 0 0 0-6-6zm-2 16a2 2 0 0 0 4 0" },
  { k: "structure", t: { ar: "القطاعات والحدود", en: "Areas & boundaries" }, tag: { ar: "الهيكل وحدود GPS", en: "Structure & GPS boundaries" }, h: { ar: "القطاعات · Zones · المباني", en: "Sectors · Zones · Buildings" }, i: "M4 20V8l8-4 8 4v12M9 20v-6h6v6M4 20h16" },
  { k: "people", t: { ar: "الموظفون", en: "Employees" }, tag: { ar: "الحسابات", en: "Accounts" }, h: { ar: "الموظفون وجهات الاتصال", en: "Employees and contacts" }, i: "M16 19v-1a4 4 0 0 0-8 0v1M12 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm7 8v-1a3 3 0 0 0-2-3m-1-9a3 3 0 0 1 0 6" },
  { k: "reports", t: { ar: "بلاغات 160", en: "160 reports" }, tag: { ar: "بلاغات مشفرة", en: "Encrypted reports" }, h: { ar: "بلاغات 160 مع الصور", en: "160 reports with photos" }, i: "M6 3h9l4 4v14H6zM14 3v5h5M9 13h7M9 17h5" },
  { k: "keys", t: { ar: "مفتاح التشفير", en: "Encryption key" }, tag: { ar: "الأمان", en: "Security" }, h: { ar: "مفتاح تشفير البلاغات", en: "Report encryption key" }, i: "M8 15a4 4 0 1 1 3-6.6L21 8v4h-2v2h-2v2h-3l-2.5-2.4A4 4 0 0 1 8 15zm-1-4h.01" },
];
const ITEM_TYPES = { sector: { ar: "قطاع", en: "sector" }, zone: { ar: "Zone", en: "zone" }, building: { ar: "مبنى", en: "building" } };
const CLASSES = { unclassified: { ar: "غير مصنفة", en: "Unclassified" }, zone2: { ar: "Zone 2", en: "Zone 2" }, zone1: { ar: "Zone 1", en: "Zone 1" }, zone0: { ar: "Zone 0", en: "Zone 0" } };
const REPORT_TYPES = { fire: { ar: "حريق", en: "Fire" }, leak: { ar: "تسرب غاز/نفط", en: "Gas/oil leak" }, injury: { ar: "إصابة", en: "Injury" },
  road: { ar: "حادث طريق", en: "Road accident" }, suspicious: { ar: "نشاط مشبوه", en: "Suspicious activity" }, hazard: { ar: "خطر سلامة", en: "Safety hazard" }, sos: { ar: "نداء استغاثة", en: "SOS" } };
const REPORT_STATUS = { new: { ar: "جديد", en: "New" }, received: { ar: "استلمه ORT", en: "Received by ORT" }, dispatched: { ar: "أُحيل للفرق", en: "Dispatched" }, closed: { ar: "مغلق", en: "Closed" } };
const CALL_LABEL = { connecting: { ar: "جارٍ التجهيز…", en: "Preparing…" }, ringing: { ar: "يرن على هاتف الموظف…", en: "Ringing the employee’s phone…" },
  connected: { ar: "متصل", en: "Connected" }, ended: { ar: "انتهت المكالمة", en: "Call ended" }, missed: { ar: "لم يرد", en: "No answer" },
  rejected: { ar: "رفض المكالمة", en: "Call declined" }, failed: { ar: "تعذّر الاتصال", en: "Couldn’t connect" } };

let savedLang = "ar";
try { savedLang = localStorage.getItem("one.lang") || "ar"; } catch (_) {}

createApp({
  setup() {
    const s = reactive({
      session: null, me: null, authErr: "", email: "", password: "", busy: false,
      tab: "map", toast: "", _tick: 0, lang: savedLang,
      sectors: [], zones: [], buildings: [], people: [], alarms: [], acks: [], reports: [],
      // structure editor
      edit: null, // {type, id?, name, parent, color, classification, code, muster_point, entry_message, boundary, coordsText}
      drawing: false,
      // alarm form
      af: { kind: "signal2", scope: "building", target_id: "", title: KINDS.signal2.title.ar, title_en: KINDS.signal2.title.en, body: KINDS.signal2.body.ar, body_en: KINDS.signal2.body.en, drill: false, second: "", confirm: false },
      selAlarm: null,
      // people
      pf: null, pe: null, avatars: {}, verifyCode: "", verifyResult: null,
      // reports
      privKey: null, pass: "", keyRow: null, hasKey: false, opened: {}, newPass: "", newPass2: "",
      // calls
      call: null, callState: "", muted: false,
    });

    let map, layers, peopleLayer, drawLayer, caller;
    const toast = (m) => { s.toast = m; setTimeout(() => (s.toast = ""), 3500); };
    const tr = (ar, en) => (s.lang === "en" ? en : ar);
    const lt = (o) => (o && typeof o === "object" ? o[s.lang] ?? o.ar : o); // i18n pick (not "L": that is Leaflet)
    const atitle = (a) => (s.lang === "en" && a.title_en ? a.title_en : a.title);
    const curNav = computed(() => NAV.find((n) => n.k === s.tab) || NAV[0]);
    function applyLang() {
      document.documentElement.lang = s.lang;
      document.documentElement.dir = s.lang === "en" ? "ltr" : "rtl";
      try { if (map) map.pm.setLang(s.lang); } catch (_) {}
    }
    function toggleLang() {
      s.lang = s.lang === "ar" ? "en" : "ar";
      try { localStorage.setItem("one.lang", s.lang); } catch (_) {}
      applyLang(); drawAreas(); drawPeople();
    }
    const byId = (arr, id) => arr.find((x) => x.id === id);
    const name = (type, id) => { const a = { sector: s.sectors, zone: s.zones, building: s.buildings, employee: s.people }[type]; const o = a && byId(a, id); return o ? (o.name || o.full_name) : "—"; };
    const fmt = (t) => t ? new Date(t).toLocaleString(s.lang === "en" ? "en-GB" : "ar-KW", { hour: "2-digit", minute: "2-digit", day: "numeric", month: "short" }) : "—";
    const ago = (t) => { void s._tick; if (!t) return "—"; const m = Math.round((Date.now() - new Date(t)) / 60000); return m < 1 ? tr("الآن", "now") : m < 60 ? tr(`قبل ${m} د`, `${m} min ago`) : m < 1440 ? tr(`قبل ${Math.round(m / 60)} س`, `${Math.round(m / 60)} h ago`) : fmt(t); };

    // ───── Auth ─────
    async function login() {
      s.busy = true; s.authErr = "";
      const { error } = await sb.auth.signInWithPassword({ email: s.email.trim(), password: s.password });
      s.busy = false; if (error) s.authErr = tr("تعذّر الدخول: تحقق من البريد وكلمة المرور.", "Sign-in failed: check the email and password.");
    }
    async function logout() { await sb.auth.signOut(); location.reload(); }

    async function boot() {
      const { data: me } = await sb.from("profiles").select("*").eq("id", s.session.user.id).single();
      s.me = me;
      if (!me || me.role !== "ort") return;
      await loadAll();
      subscribe();
      await nextTick(); initMap();
    }

    async function loadAll() {
      const [a, b, c, d, e, f, g, k] = await Promise.all([
        sb.from("sectors").select("*").order("created_at"),
        sb.from("zones").select("*").order("created_at"),
        sb.from("buildings").select("*").order("created_at"),
        sb.from("profiles").select("*").order("full_name"),
        sb.from("alarms").select("*").order("created_at", { ascending: false }).limit(50),
        sb.from("alarm_acks").select("*"),
        sb.from("reports").select("*").order("created_at", { ascending: false }).limit(200),
        sb.from("org_private_key").select("*").maybeSingle(),
      ]);
      s.sectors = a.data || []; s.zones = b.data || []; s.buildings = c.data || []; s.people = d.data || [];
      s.alarms = e.data || []; s.acks = f.data || []; s.reports = g.data || [];
      s.keyRow = k.data; s.hasKey = !!k.data;
      if (!s.selAlarm) { const act = s.alarms.find((x) => x.active); if (act) s.selAlarm = act.id; }
      loadAvatars();
    }

    function upsertLocal(arr, row, key = (r) => r.id) { const i = arr.findIndex((x) => key(x) === key(row)); if (i >= 0) arr[i] = row; else arr.unshift(row); }
    function subscribe() {
      sb.channel("ort-live")
        .on("postgres_changes", { event: "*", schema: "public", table: "alarms" }, ({ new: r }) => { r && r.id && upsertLocal(s.alarms, r); })
        .on("postgres_changes", { event: "*", schema: "public", table: "alarm_acks" }, ({ new: r }) => { if (r && r.alarm_id) upsertLocal(s.acks, r, (x) => x.alarm_id + x.user_id); drawPeople(); })
        .on("postgres_changes", { event: "*", schema: "public", table: "profiles" }, ({ new: r }) => { if (r && r.id) { upsertLocal(s.people, r); drawPeople(); } })
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "reports" }, ({ new: r }) => { s.reports.unshift(r); toast(tr("بلاغ جديد وارد إلى 160 — ", "New 160 report — ") + (lt(REPORT_TYPES[r.type]) || r.type)); beep(); })
        .subscribe();
    }
    function beep() { try { const a = new AudioContext(), o = a.createOscillator(); o.frequency.value = 880; o.connect(a.destination); o.start(); o.stop(a.currentTime + 0.25); } catch (_) {} }

    // ───── Map ─────
    function initMap() {
      if (map) return;
      map = L.map("map", { zoomControl: true, attributionControl: true }).setView(C.MAP_CENTER, 12);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: "© OpenStreetMap" }).addTo(map);
      layers = L.layerGroup().addTo(map); peopleLayer = L.layerGroup().addTo(map); drawLayer = L.layerGroup().addTo(map);
      applyLang();
      map.on("pm:create", (e) => {
        const pts = e.layer.getLatLngs()[0].map((p) => [+p.lat.toFixed(6), +p.lng.toFixed(6)]);
        map.removeLayer(e.layer); s.drawing = false;
        if (s.edit) { s.edit.boundary = pts; s.edit.coordsText = pts.map((p) => p.join(", ")).join("\n"); drawEditPreview(); }
      });
      drawAreas(); drawPeople(); fitAll();
    }
    function poly(points, opts) { return points && points.length > 2 ? L.polygon(points, opts) : null; }
    function drawAreas() {
      if (!layers) return; layers.clearLayers();
      s.sectors.forEach((x) => { const p = poly(x.boundary, { color: x.color, weight: 2, fillOpacity: 0.05, dashArray: "6 6" }); p && p.bindTooltip(tr("قطاع: ", "Sector: ") + x.name).addTo(layers); });
      s.zones.forEach((x) => { const sec = byId(s.sectors, x.sector_id); const p = poly(x.boundary, { color: x.classification === "unclassified" ? (sec?.color || "#2B4C9B") : "#E07B29", weight: 2, fillOpacity: 0.1 }); p && p.bindTooltip(`${x.name} · ${lt(CLASSES[x.classification])}`).addTo(layers); });
      s.buildings.forEach((x) => { const p = poly(x.boundary, { color: "#1F3A7A", weight: 2, fillColor: "#2B4C9B", fillOpacity: 0.18 }); p && p.bindTooltip(tr("مبنى: ", "Building: ") + x.name, { permanent: false }).addTo(layers); });
    }
    function statusFor(uid) {
      const a = s.alarms.find((x) => x.active && x.id === s.selAlarm) || s.alarms.find((x) => x.active);
      if (!a) return null; const k = s.acks.find((x) => x.alarm_id === a.id && x.user_id === uid); return k ? k.status : null;
    }
    const STATUS_COLOR = { safe: "#2E9E5B", received: "#E5B80B", need_help: "#E07B29", injured: "#C62828", trapped: "#C62828" };
    function drawPeople() {
      if (!peopleLayer) return; peopleLayer.clearLayers();
      s.people.filter((p) => p.last_lat && p.role !== "ort").forEach((p) => {
        const st = statusFor(p.id);
        L.circleMarker([p.last_lat, p.last_lng], { radius: 7, color: "#ffffff", weight: 2, fillColor: STATUS_COLOR[st] || (p.online ? "#2B4C9B" : "#94A3B8"), fillOpacity: 1 })
          .bindPopup(`<b>${esc(p.full_name)}</b><br>${esc(p.employee_no || "")} · ${tr("فصيلة", "Blood")} ${esc(p.blood_type || "—")}<br>${esc(name("building", p.cur_building_id))} · ${tr("آخر ظهور", "last seen")} ${ago(p.last_seen)}<br>
            ${st ? tr("الحالة: ", "Status: ") + lt(STATUS[st][0]) + "<br>" : ""}<button class="mini" onclick="window.__kocCall('${p.id}')">${tr("اتصال صوتي", "Voice call")}</button>`)
          .addTo(peopleLayer);
      });
    }
    function fitAll() {
      const all = [...s.sectors, ...s.zones, ...s.buildings].filter((x) => x.boundary && x.boundary.length > 2).flatMap((x) => x.boundary);
      if (all.length) map.fitBounds(all, { padding: [30, 30] });
    }
    function focus(item) { if (item.boundary && item.boundary.length > 2) map.fitBounds(item.boundary, { padding: [40, 40] }); }
    const esc = (t) => String(t ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
    watch(() => [s.sectors, s.zones, s.buildings], drawAreas, { deep: true });
    watch(() => s.selAlarm, drawPeople);
    watch(() => s.tab, () => nextTick(() => map && map.invalidateSize()));

    // ───── Structure editor ─────
    function newItem(type, parent = "") {
      s.edit = { type, id: null, name: "", parent, color: "#2B4C9B", classification: "unclassified", code: "", muster_point: "", entry_message: "", boundary: null, coordsText: "" };
      drawLayer && drawLayer.clearLayers();
    }
    function editItem(type, x) {
      s.edit = { type, id: x.id, name: x.name, parent: x.sector_id || x.zone_id || "", color: x.color || "#0e7490", classification: x.classification || "unclassified",
        code: x.code || "", muster_point: x.muster_point || "", entry_message: x.entry_message || "", boundary: x.boundary, coordsText: (x.boundary || []).map((p) => p.join(", ")).join("\n") };
      focus(x); drawEditPreview();
    }
    function startDraw() { s.drawing = true; map.pm.enableDraw("Polygon", { snappable: true, templineStyle: { color: "#E5B80B" }, pathOptions: { color: "#E5B80B" } }); }
    function cancelDraw() { s.drawing = false; map.pm.disableDraw(); }
    function parseCoords() {
      const pts = s.edit.coordsText.split(/\n+/).map((l) => l.split(/[,\s]+/).filter(Boolean).map(Number)).filter((p) => p.length === 2 && p.every((n) => !isNaN(n)));
      if (pts.length < 3) return toast(tr("أدخل 3 نقاط على الأقل بصيغة: خط العرض, خط الطول", "Enter at least 3 points as: latitude, longitude"));
      s.edit.boundary = pts; drawEditPreview(); map.fitBounds(pts, { padding: [40, 40] });
    }
    function useMyGps() {
      if (!navigator.geolocation) return toast(tr("المتصفح لا يدعم تحديد الموقع", "This browser has no location support"));
      navigator.geolocation.getCurrentPosition((p) => {
        const line = `${p.coords.latitude.toFixed(6)}, ${p.coords.longitude.toFixed(6)}`;
        s.edit.coordsText = (s.edit.coordsText ? s.edit.coordsText + "\n" : "") + line; toast(tr("أُضيفت نقطة GPS · الدقة ", "GPS point added · accuracy ") + Math.round(p.coords.accuracy) + tr(" م", " m"));
      }, () => toast(tr("تعذّر قراءة GPS", "Couldn’t read GPS")), { enableHighAccuracy: true });
    }
    function drawEditPreview() { drawLayer.clearLayers(); const p = poly(s.edit?.boundary, { color: "#E5B80B", weight: 3, fillOpacity: 0.2 }); p && p.addTo(drawLayer); }
    async function saveItem() {
      const e = s.edit; if (!e.name.trim()) return toast(tr("اكتب الاسم أولًا", "Enter a name first"));
      const table = { sector: "sectors", zone: "zones", building: "buildings" }[e.type];
      const row = { name: e.name.trim(), boundary: e.boundary, entry_message: e.entry_message || null };
      if (e.type === "sector") row.color = e.color;
      if (e.type === "zone") { if (!e.parent) return toast(tr("اختر القطاع", "Choose a sector")); row.sector_id = e.parent; row.classification = e.classification; }
      if (e.type === "building") { if (!e.parent) return toast(tr("اختر الـ Zone", "Choose a zone")); row.zone_id = e.parent; row.code = e.code || null; row.muster_point = e.muster_point || null; }
      const q = e.id ? sb.from(table).update(row).eq("id", e.id) : sb.from(table).insert(row);
      const { error } = await q; if (error) return toast(tr("خطأ: ", "Error: ") + error.message);
      toast(tr("تم الحفظ", "Saved")); s.edit = null; drawLayer.clearLayers(); await loadAll();
    }
    async function deleteItem() {
      const e = s.edit; if (!e.id) return;
      if (!e.confirmDel) { e.confirmDel = true; return; }
      const table = { sector: "sectors", zone: "zones", building: "buildings" }[e.type];
      const { error } = await sb.from(table).delete().eq("id", e.id); if (error) return toast(error.message);
      s.edit = null; drawLayer.clearLayers(); await loadAll(); toast(tr("تم الحذف", "Deleted"));
    }

    // ───── Alarms ─────
    const targets = computed(() => ({ employee: s.people.filter((p) => p.role !== "ort").map((p) => ({ id: p.id, name: p.full_name + (p.employee_no ? " · " + p.employee_no : "") })),
      building: s.buildings, zone: s.zones, sector: s.sectors, all: [] }[s.af.scope]));
    function setKind(k) { s.af.kind = k; s.af.title = KINDS[k].title.ar; s.af.title_en = KINDS[k].title.en; s.af.body = KINDS[k].body.ar; s.af.body_en = KINDS[k].body.en; }
    function inScope(p, a) {
      if (a.scope === "all") return !!(p.cur_sector_id || p.cur_zone_id || p.cur_building_id);
      if (a.scope === "employee") return p.id === a.target_id;
      return p[{ sector: "cur_sector_id", zone: "cur_zone_id", building: "cur_building_id" }[a.scope]] === a.target_id;
    }
    const reach = computed(() => {
      const a = s.af; if (a.scope !== "all" && !a.target_id) return 0;
      return s.people.filter((p) => p.role !== "ort" && inScope(p, a)).length;
    });
    async function launch() {
      const a = s.af;
      if (a.scope !== "all" && !a.target_id) return toast(tr("اختر الهدف", "Choose a target"));
      if (!a.title.trim() && !a.title_en.trim()) return toast(tr("اكتب عنوان الإنذار", "Enter the alarm title"));
      if (a.kind !== "message" && (!a.second.trim() || !a.confirm)) return toast(tr("الإطلاق يحتاج تأكيدًا ثنائيًا: اسم الضابط الثاني وتأشير التأكيد", "Launch needs dual confirmation: the second officer’s name and the tick box"));
      const { data, error } = await sb.from("alarms").insert({ kind: a.kind, title: a.title.trim() || a.title_en.trim(), body: a.body, title_en: a.title_en.trim() || null, body_en: a.body_en || null, scope: a.scope, target_id: a.scope === "all" ? null : a.target_id,
        drill: a.drill, created_by: s.me.id, confirmed_by_name: a.second.trim() || null, active: a.kind !== "message" && a.kind !== "signal3" }).select().single();
      if (error) return toast(tr("تعذّر الإطلاق: ", "Launch failed: ") + error.message);
      if (a.kind === "signal3") await sb.from("alarms").update({ active: false, closed_at: new Date().toISOString() }).eq("active", true).eq("scope", a.scope).filter("target_id", a.scope === "all" ? "is" : "eq", a.scope === "all" ? null : a.target_id);
      upsertLocal(s.alarms, data); if (data.active) s.selAlarm = data.id;
      a.confirm = false; a.second = ""; toast(`${tr("أُطلق", "Launched")}: ${atitle(data)} → ${lt(SCOPES[data.scope])}${data.scope !== "all" ? " · " + name(data.scope, data.target_id) : ""}`);
      await loadAll();
    }
    async function closeAlarm(al, allClear) {
      if (allClear) {
        await sb.from("alarms").insert({ kind: "signal3", title: KINDS.signal3.title.ar, body: KINDS.signal3.body.ar, title_en: KINDS.signal3.title.en, body_en: KINDS.signal3.body.en, scope: al.scope, target_id: al.target_id, drill: al.drill, created_by: s.me.id, active: false, confirmed_by_name: s.me.full_name });
      }
      await sb.from("alarms").update({ active: false, closed_at: new Date().toISOString() }).eq("id", al.id);
      await loadAll(); toast(allClear ? tr("أُرسلت الإشارة 3 · زوال الخطر وأُغلق الحادث", "Signal 3 · All clear sent and the incident closed") : tr("أُغلق الإنذار", "Alarm closed"));
    }
    function alarmRoster(al) {
      const acks = s.acks.filter((k) => k.alarm_id === al.id);
      const ids = new Set([...acks.map((k) => k.user_id), ...s.people.filter((p) => p.role !== "ort" && inScope(p, al)).map((p) => p.id)]);
      const order = { trapped: 0, injured: 1, need_help: 2, none: 3, received: 4, safe: 5 };
      return [...ids].map((id) => { const p = byId(s.people, id) || { id, full_name: "—" }; const k = acks.find((x) => x.user_id === id); return { p, st: k ? k.status : "none", k }; })
        .sort((x, y) => order[x.st] - order[y.st]);
    }
    function counts(al) {
      const r = alarmRoster(al), c = { total: r.length, safe: 0, received: 0, need_help: 0, injured: 0, trapped: 0, none: 0 };
      r.forEach((x) => c[x.st]++); c.pct = c.total ? Math.round((c.safe / c.total) * 100) : 0; return c;
    }
    const selAlarmObj = computed(() => byId(s.alarms, s.selAlarm));
    const activeAlarms = computed(() => s.alarms.filter((a) => a.active));

    // ───── People ─────
    function newPerson() { s.pf = { email: "", password: "", full_name: "", employee_no: "", phone: "", blood_type: "O+", role: "employee" }; }
    async function savePerson() {
      const f = s.pf; if (!f.email || f.password.length < 8 || !f.full_name) return toast(tr("البريد والاسم وكلمة مرور من 8 أحرف على الأقل مطلوبة", "Email, name and a password of at least 8 characters are required"));
      const { data, error } = await sb.functions.invoke("manage-users", { body: { action: "create", ...f } });
      if (error || data?.error) return toast(tr("تعذّر الإنشاء: ", "Couldn’t create: ") + (data?.error || error.message));
      s.pf = null; toast(tr("أُنشئ الحساب — سلّم الموظف بيانات الدخول للتطبيق", "Account created — give the employee their sign-in details")); await loadAll();
    }
    async function loadAvatars() {
      const paths = s.people.filter((p) => p.photo_path).map((p) => p.photo_path);
      if (!paths.length) return;
      const { data } = await sb.storage.from("avatars").createSignedUrls(paths, 3600);
      const map = {};
      (data || []).forEach((d, i) => { if (d.signedUrl) map[paths[i]] = d.signedUrl; });
      s.avatars = map;
    }
    const avatar = (p) => (p && p.photo_path ? s.avatars[p.photo_path] : null);
    function editPerson(p) {
      s.pe = { id: p.id, full_name: p.full_name || "", employee_no: p.employee_no || "", job_title: p.job_title || "", department: p.department || "",
        phone: p.phone || "", blood_type: p.blood_type || "O+", civil_id: p.civil_id || "", active: p.active !== false, role: p.role,
        photo_path: p.photo_path, file: null, preview: avatar(p) };
    }
    // Resize to max 640px JPEG before upload (official ID photo)
    function pickPhoto(ev) {
      const f = ev.target.files && ev.target.files[0]; if (!f) return;
      const img = new Image(), url = URL.createObjectURL(f);
      img.onload = () => {
        const k = Math.min(1, 640 / Math.max(img.width, img.height));
        const c = document.createElement("canvas"); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
        c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
        c.toBlob((b) => { s.pe.file = b; s.pe.preview = URL.createObjectURL(b); }, "image/jpeg", 0.88);
        URL.revokeObjectURL(url);
      };
      img.src = url;
    }
    async function savePersonEdit() {
      const e = s.pe; if (!e.full_name.trim()) return toast(tr("الاسم مطلوب", "Name is required"));
      let photo_path = e.photo_path;
      if (e.file) {
        photo_path = `${e.id}/photo.jpg`;
        const up = await sb.storage.from("avatars").upload(photo_path, e.file, { upsert: true, contentType: "image/jpeg" });
        if (up.error) return toast(tr("تعذّر رفع الصورة: ", "Photo upload failed: ") + up.error.message);
      }
      const row = { full_name: e.full_name.trim(), employee_no: e.employee_no || null, job_title: e.job_title || null, department: e.department || null,
        phone: e.phone || null, blood_type: e.blood_type || null, civil_id: e.civil_id || null, active: e.active, role: e.role, photo_path };
      const { error } = await sb.from("profiles").update(row).eq("id", e.id);
      if (error) return toast(tr("خطأ: ", "Error: ") + error.message);
      s.pe = null; toast(tr("حُفظت بيانات الهوية", "ID details saved")); await loadAll();
    }
    async function verifyId() {
      s.verifyResult = null; const code = s.verifyCode.trim(); if (!code) return;
      const { data, error } = await sb.functions.invoke("id-token", { body: { verify: code } });
      s.verifyResult = error ? { valid: false } : data;
    }
    async function updatePerson(p, field, value) { const { error } = await sb.from("profiles").update({ [field]: value }).eq("id", p.id); if (error) toast(error.message); }

    // ───── Calls ─────
    async function callPerson(id) {
      const p = byId(s.people, id); if (!p) return;
      if (s.call) return toast(tr("هناك مكالمة جارية", "A call is already in progress"));
      s.call = p; s.callState = "connecting"; s.muted = false;
      caller = window.KocCall(sb, (st) => { s.callState = st; if (["ended", "missed", "rejected", "failed"].includes(st)) setTimeout(() => { if (s.callState === st) s.call = null; }, 2500); });
      try { await caller.start(p.id, s.me.full_name || "ORT · 160"); } catch (e) { s.callState = "failed"; toast(tr("تعذّر بدء المكالمة: ", "Couldn’t start the call: ") + (e.message || e)); setTimeout(() => (s.call = null), 2000); }
    }
    window.__kocCall = callPerson;
    function hangup() { caller && caller.end("ended"); }
    function toggleMute() { s.muted = !s.muted; caller && caller.mute(s.muted); }

    // ───── Reports & keys ─────
    async function setupKeys() {
      if (s.newPass.length < 10) return toast(tr("عبارة المرور 10 أحرف على الأقل", "The passphrase needs at least 10 characters"));
      if (s.newPass !== s.newPass2) return toast(tr("عبارتا المرور غير متطابقتين", "The passphrases don’t match"));
      if (s.hasKey && !s.confirmRotate) { s.confirmRotate = true; return; }
      const k = await KocCrypto.createOrgKeys(s.newPass);
      const a = await sb.from("org_public_key").upsert({ id: 1, jwk: k.publicJwk, updated_at: new Date().toISOString() });
      const b = await sb.from("org_private_key").upsert({ id: 1, wrapped: k.wrapped, salt: k.salt, iv: k.iv, updated_at: new Date().toISOString() });
      if (a.error || b.error) return toast(tr("خطأ: ", "Error: ") + (a.error || b.error).message);
      s.privKey = k.privateKey; s.newPass = s.newPass2 = ""; s.confirmRotate = false; await loadAll(); toast(tr("أُنشئ مفتاح التشفير. احفظ عبارة المرور في مكان آمن.", "Encryption key created. Keep the passphrase somewhere safe."));
    }
    async function unlockKey() {
      try { s.privKey = await KocCrypto.unlock(s.keyRow, s.pass); s.pass = ""; toast(tr("فُتح المفتاح لهذه الجلسة فقط", "Key unlocked for this session only")); }
      catch (_) { toast(tr("عبارة المرور غير صحيحة", "Wrong passphrase")); }
    }
    async function openReport(r) {
      if (!s.privKey) return toast(tr("افتح مفتاح التشفير أولًا", "Unlock the encryption key first"));
      try {
        const { key, payload } = await KocCrypto.decryptReport(s.privKey, r);
        const photos = [];
        for (const path of r.photo_paths || []) {
          const { data, error } = await sb.storage.from("reports").download(path);
          if (error) continue;
          const raw = KocCrypto.unb64(await data.text());
          const bytes = await KocCrypto.openBytes(key, raw);
          photos.push(URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" })));
        }
        s.opened[r.id] = { ...payload, photos };
        if (r.status === "new") await setReportStatus(r, "received");
      } catch (e) { toast(tr("تعذّر فك التشفير: المفتاح لا يطابق هذا البلاغ", "Couldn’t decrypt: the key doesn’t match this report")); }
    }
    async function setReportStatus(r, st) { const { error } = await sb.from("reports").update({ status: st }).eq("id", r.id); if (!error) r.status = st; }

    // ───── KPIs ─────
    const kpi = computed(() => ({
      online: s.people.filter((p) => p.role !== "ort" && p.online).length,
      inside: s.people.filter((p) => p.role !== "ort" && (p.cur_sector_id || p.cur_zone_id || p.cur_building_id)).length,
      staff: s.people.filter((p) => p.role !== "ort").length,
      newReports: s.reports.filter((r) => r.status === "new").length,
      active: activeAlarms.value.length,
    }));
    const zonesOf = (sid) => s.zones.filter((z) => z.sector_id === sid);
    const buildingsOf = (zid) => s.buildings.filter((b) => b.zone_id === zid);
    const peopleIn = (field, id) => s.people.filter((p) => p[field] === id).length;

    onMounted(async () => {
      const { data } = await sb.auth.getSession(); s.session = data.session;
      sb.auth.onAuthStateChange((_e, sess) => { const was = !!s.session; s.session = sess; if (sess && !was) boot(); });
      applyLang();
      if (s.session) boot();
      setInterval(() => { s._tick = Date.now(); }, 30000);
    });

    return { s, L: lt, avatar, editPerson, pickPhoto, savePersonEdit, verifyId, NAV, ITEM_TYPES, KINDS, tr, atitle, curNav, toggleLang, SCOPES, STATUS, CLASSES, REPORT_TYPES, REPORT_STATUS, CALL_LABEL, login, logout, name, fmt, ago,
      newItem, editItem, startDraw, cancelDraw, parseCoords, useMyGps, saveItem, deleteItem, focus, fitAll,
      targets, setKind, reach, launch, closeAlarm, alarmRoster, counts, selAlarmObj, activeAlarms,
      newPerson, savePerson, updatePerson, callPerson, hangup, toggleMute,
      setupKeys, unlockKey, openReport, setReportStatus, kpi, zonesOf, buildingsOf, peopleIn };
  },
}).mount("#app");
