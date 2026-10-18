/* KOC ONE · ORT dashboard (ECC-160) — Vue 3 (no build step) + Leaflet + Supabase */
const { createApp, reactive, computed, onMounted, nextTick, watch } = Vue;
const C = window.KOC_CONFIG;
const sb = supabase.createClient(C.SUPABASE_URL, C.SUPABASE_KEY);

const KINDS = {
  signal1: { label: "الإشارة 1 · طوارئ", short: "طوارئ", title: "الإشارة 1 — طوارئ",
    body: "1. ابقَ متأهبًا في مكانك\n2. استمع لتعليمات النداء العام\n3. أوقف الأعمال الخطرة وأمّن المعدات", cls: "k1" },
  signal2: { label: "الإشارة 2 · إخلاء", short: "إخلاء", title: "الإشارة 2 — إخلاء",
    body: "1. أخلِ المنطقة وفق تعليمات النداء العام\n2. استخدم مسارات الإخلاء الآمنة — لا مصاعد\n3. توجّه إلى نقطة التجمع\n4. سجّل حالتك في التطبيق عند الوصول", cls: "k2" },
  signal3: { label: "الإشارة 3 · زوال الخطر", short: "زوال الخطر", title: "الإشارة 3 — زوال الخطر",
    body: "1. عُد إلى مكان عملك\n2. اتبع تعليمات مسؤول الإخلاء\n3. أُغلق الحادث وسُجّل", cls: "k3" },
  message: { label: "رسالة تنبيه", short: "تنبيه", title: "تنبيه سلامة", body: "", cls: "km" },
};
const SCOPES = { employee: "موظف", building: "مبنى", zone: "Zone", sector: "قطاع", all: "جميع القطاعات" };
const STATUS = {
  received: ["استلم — لم يرد", "st-wait"], safe: ["آمن", "st-ok"], need_help: ["يحتاج مساعدة", "st-warn"],
  injured: ["مصاب", "st-bad"], trapped: ["محتجز", "st-bad"], none: ["لم يستلم", "st-none"],
};
const CLASSES = { unclassified: "غير مصنفة", zone2: "Zone 2", zone1: "Zone 1", zone0: "Zone 0" };
const REPORT_TYPES = { fire: "حريق", leak: "تسرب غاز/نفط", injury: "إصابة", road: "حادث طريق", suspicious: "نشاط مشبوه", hazard: "خطر سلامة", sos: "نداء استغاثة" };
const REPORT_STATUS = { new: "جديد", received: "استلمه ORT", dispatched: "أُحيل للفرق", closed: "مغلق" };

createApp({
  setup() {
    const s = reactive({
      session: null, me: null, authErr: "", email: "", password: "", busy: false,
      tab: "map", toast: "", _tick: 0,
      sectors: [], zones: [], buildings: [], people: [], alarms: [], acks: [], reports: [],
      // structure editor
      edit: null, // {type, id?, name, parent, color, classification, code, muster_point, entry_message, boundary, coordsText}
      drawing: false,
      // alarm form
      af: { kind: "signal2", scope: "building", target_id: "", title: KINDS.signal2.title, body: KINDS.signal2.body, drill: false, second: "", confirm: false },
      selAlarm: null,
      // people
      pf: null,
      // reports
      privKey: null, pass: "", keyRow: null, hasKey: false, opened: {}, newPass: "", newPass2: "",
      // calls
      call: null, callState: "", muted: false,
    });

    let map, layers, peopleLayer, drawLayer, caller;
    const toast = (m) => { s.toast = m; setTimeout(() => (s.toast = ""), 3500); };
    const byId = (arr, id) => arr.find((x) => x.id === id);
    const name = (type, id) => { const a = { sector: s.sectors, zone: s.zones, building: s.buildings, employee: s.people }[type]; const o = a && byId(a, id); return o ? (o.name || o.full_name) : "—"; };
    const fmt = (t) => t ? new Date(t).toLocaleString("ar-KW", { hour: "2-digit", minute: "2-digit", day: "numeric", month: "short" }) : "—";
    const ago = (t) => { void s._tick; if (!t) return "—"; const m = Math.round((Date.now() - new Date(t)) / 60000); return m < 1 ? "الآن" : m < 60 ? `قبل ${m} د` : m < 1440 ? `قبل ${Math.round(m / 60)} س` : fmt(t); };

    // ───── Auth ─────
    async function login() {
      s.busy = true; s.authErr = "";
      const { error } = await sb.auth.signInWithPassword({ email: s.email.trim(), password: s.password });
      s.busy = false; if (error) s.authErr = "تعذّر الدخول: تحقق من البريد وكلمة المرور.";
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
    }

    function upsertLocal(arr, row, key = (r) => r.id) { const i = arr.findIndex((x) => key(x) === key(row)); if (i >= 0) arr[i] = row; else arr.unshift(row); }
    function subscribe() {
      sb.channel("ort-live")
        .on("postgres_changes", { event: "*", schema: "public", table: "alarms" }, ({ new: r }) => { r && r.id && upsertLocal(s.alarms, r); })
        .on("postgres_changes", { event: "*", schema: "public", table: "alarm_acks" }, ({ new: r }) => { if (r && r.alarm_id) upsertLocal(s.acks, r, (x) => x.alarm_id + x.user_id); drawPeople(); })
        .on("postgres_changes", { event: "*", schema: "public", table: "profiles" }, ({ new: r }) => { if (r && r.id) { upsertLocal(s.people, r); drawPeople(); } })
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "reports" }, ({ new: r }) => { s.reports.unshift(r); toast("بلاغ جديد وارد إلى 160 — " + (REPORT_TYPES[r.type] || r.type)); beep(); })
        .subscribe();
    }
    function beep() { try { const a = new AudioContext(), o = a.createOscillator(); o.frequency.value = 880; o.connect(a.destination); o.start(); o.stop(a.currentTime + 0.25); } catch (_) {} }

    // ───── Map ─────
    function initMap() {
      if (map) return;
      map = L.map("map", { zoomControl: true, attributionControl: true }).setView(C.MAP_CENTER, 12);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: "© OpenStreetMap" }).addTo(map);
      layers = L.layerGroup().addTo(map); peopleLayer = L.layerGroup().addTo(map); drawLayer = L.layerGroup().addTo(map);
      try { map.pm.setLang("ar"); } catch (_) {}
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
      s.sectors.forEach((x) => { const p = poly(x.boundary, { color: x.color, weight: 2, fillOpacity: 0.05, dashArray: "6 6" }); p && p.bindTooltip("قطاع: " + x.name).addTo(layers); });
      s.zones.forEach((x) => { const sec = byId(s.sectors, x.sector_id); const p = poly(x.boundary, { color: x.classification === "unclassified" ? (sec?.color || "#38bdf8") : "#f97316", weight: 2, fillOpacity: 0.1 }); p && p.bindTooltip(`${x.name} · ${CLASSES[x.classification]}`).addTo(layers); });
      s.buildings.forEach((x) => { const p = poly(x.boundary, { color: "#e2e8f0", weight: 1.5, fillOpacity: 0.25 }); p && p.bindTooltip("مبنى: " + x.name, { permanent: false }).addTo(layers); });
    }
    function statusFor(uid) {
      const a = s.alarms.find((x) => x.active && x.id === s.selAlarm) || s.alarms.find((x) => x.active);
      if (!a) return null; const k = s.acks.find((x) => x.alarm_id === a.id && x.user_id === uid); return k ? k.status : null;
    }
    const STATUS_COLOR = { safe: "#22c55e", received: "#facc15", need_help: "#fb923c", injured: "#ef4444", trapped: "#ef4444" };
    function drawPeople() {
      if (!peopleLayer) return; peopleLayer.clearLayers();
      s.people.filter((p) => p.last_lat && p.role !== "ort").forEach((p) => {
        const st = statusFor(p.id);
        L.circleMarker([p.last_lat, p.last_lng], { radius: 7, color: "#0b1220", weight: 2, fillColor: STATUS_COLOR[st] || (p.online ? "#38bdf8" : "#64748b"), fillOpacity: 1 })
          .bindPopup(`<b>${esc(p.full_name)}</b><br>${esc(p.employee_no || "")} · فصيلة ${esc(p.blood_type || "—")}<br>${esc(name("building", p.cur_building_id))} · آخر ظهور ${ago(p.last_seen)}<br>
            ${st ? "الحالة: " + STATUS[st][0] + "<br>" : ""}<button class="mini" onclick="window.__kocCall('${p.id}')">اتصال صوتي</button>`)
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
      s.edit = { type, id: null, name: "", parent, color: "#0e7490", classification: "unclassified", code: "", muster_point: "", entry_message: "", boundary: null, coordsText: "" };
      drawLayer && drawLayer.clearLayers();
    }
    function editItem(type, x) {
      s.edit = { type, id: x.id, name: x.name, parent: x.sector_id || x.zone_id || "", color: x.color || "#0e7490", classification: x.classification || "unclassified",
        code: x.code || "", muster_point: x.muster_point || "", entry_message: x.entry_message || "", boundary: x.boundary, coordsText: (x.boundary || []).map((p) => p.join(", ")).join("\n") };
      focus(x); drawEditPreview();
    }
    function startDraw() { s.drawing = true; map.pm.enableDraw("Polygon", { snappable: true, templineStyle: { color: "#facc15" }, pathOptions: { color: "#facc15" } }); }
    function cancelDraw() { s.drawing = false; map.pm.disableDraw(); }
    function parseCoords() {
      const pts = s.edit.coordsText.split(/\n+/).map((l) => l.split(/[,\s]+/).filter(Boolean).map(Number)).filter((p) => p.length === 2 && p.every((n) => !isNaN(n)));
      if (pts.length < 3) return toast("أدخل 3 نقاط على الأقل بصيغة: خط العرض, خط الطول");
      s.edit.boundary = pts; drawEditPreview(); map.fitBounds(pts, { padding: [40, 40] });
    }
    function useMyGps() {
      if (!navigator.geolocation) return toast("المتصفح لا يدعم تحديد الموقع");
      navigator.geolocation.getCurrentPosition((p) => {
        const line = `${p.coords.latitude.toFixed(6)}, ${p.coords.longitude.toFixed(6)}`;
        s.edit.coordsText = (s.edit.coordsText ? s.edit.coordsText + "\n" : "") + line; toast("أُضيفت نقطة GPS · الدقة " + Math.round(p.coords.accuracy) + " م");
      }, () => toast("تعذّر قراءة GPS"), { enableHighAccuracy: true });
    }
    function drawEditPreview() { drawLayer.clearLayers(); const p = poly(s.edit?.boundary, { color: "#facc15", weight: 3, fillOpacity: 0.15 }); p && p.addTo(drawLayer); }
    async function saveItem() {
      const e = s.edit; if (!e.name.trim()) return toast("اكتب الاسم أولًا");
      const table = { sector: "sectors", zone: "zones", building: "buildings" }[e.type];
      const row = { name: e.name.trim(), boundary: e.boundary, entry_message: e.entry_message || null };
      if (e.type === "sector") row.color = e.color;
      if (e.type === "zone") { if (!e.parent) return toast("اختر القطاع"); row.sector_id = e.parent; row.classification = e.classification; }
      if (e.type === "building") { if (!e.parent) return toast("اختر الـ Zone"); row.zone_id = e.parent; row.code = e.code || null; row.muster_point = e.muster_point || null; }
      const q = e.id ? sb.from(table).update(row).eq("id", e.id) : sb.from(table).insert(row);
      const { error } = await q; if (error) return toast("خطأ: " + error.message);
      toast("تم الحفظ"); s.edit = null; drawLayer.clearLayers(); await loadAll();
    }
    async function deleteItem() {
      const e = s.edit; if (!e.id) return;
      if (!e.confirmDel) { e.confirmDel = true; return; }
      const table = { sector: "sectors", zone: "zones", building: "buildings" }[e.type];
      const { error } = await sb.from(table).delete().eq("id", e.id); if (error) return toast(error.message);
      s.edit = null; drawLayer.clearLayers(); await loadAll(); toast("تم الحذف");
    }

    // ───── Alarms ─────
    const targets = computed(() => ({ employee: s.people.filter((p) => p.role !== "ort").map((p) => ({ id: p.id, name: p.full_name + (p.employee_no ? " · " + p.employee_no : "") })),
      building: s.buildings, zone: s.zones, sector: s.sectors, all: [] }[s.af.scope]));
    function setKind(k) { s.af.kind = k; s.af.title = KINDS[k].title; s.af.body = KINDS[k].body; }
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
      if (a.scope !== "all" && !a.target_id) return toast("اختر الهدف");
      if (!a.title.trim()) return toast("اكتب عنوان الإنذار");
      if (a.kind !== "message" && (!a.second.trim() || !a.confirm)) return toast("الإطلاق يحتاج تأكيدًا ثنائيًا: اسم الضابط الثاني وتأشير التأكيد");
      const { data, error } = await sb.from("alarms").insert({ kind: a.kind, title: a.title.trim(), body: a.body, scope: a.scope, target_id: a.scope === "all" ? null : a.target_id,
        drill: a.drill, created_by: s.me.id, confirmed_by_name: a.second.trim() || null, active: a.kind !== "message" && a.kind !== "signal3" }).select().single();
      if (error) return toast("تعذّر الإطلاق: " + error.message);
      if (a.kind === "signal3") await sb.from("alarms").update({ active: false, closed_at: new Date().toISOString() }).eq("active", true).eq("scope", a.scope).filter("target_id", a.scope === "all" ? "is" : "eq", a.scope === "all" ? null : a.target_id);
      upsertLocal(s.alarms, data); if (data.active) s.selAlarm = data.id;
      a.confirm = false; a.second = ""; toast(`أُطلق: ${data.title} → ${SCOPES[data.scope]}${data.scope !== "all" ? " · " + name(data.scope, data.target_id) : ""}`);
      await loadAll();
    }
    async function closeAlarm(al, allClear) {
      if (allClear) {
        await sb.from("alarms").insert({ kind: "signal3", title: KINDS.signal3.title, body: KINDS.signal3.body, scope: al.scope, target_id: al.target_id, drill: al.drill, created_by: s.me.id, active: false, confirmed_by_name: s.me.full_name });
      }
      await sb.from("alarms").update({ active: false, closed_at: new Date().toISOString() }).eq("id", al.id);
      await loadAll(); toast(allClear ? "أُرسلت الإشارة 3 · زوال الخطر وأُغلق الحادث" : "أُغلق الإنذار");
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
      const f = s.pf; if (!f.email || f.password.length < 8 || !f.full_name) return toast("البريد والاسم وكلمة مرور من 8 أحرف على الأقل مطلوبة");
      const { data, error } = await sb.functions.invoke("manage-users", { body: { action: "create", ...f } });
      if (error || data?.error) return toast("تعذّر الإنشاء: " + (data?.error || error.message));
      s.pf = null; toast("أُنشئ الحساب — سلّم الموظف بيانات الدخول للتطبيق"); await loadAll();
    }
    async function updatePerson(p, field, value) { const { error } = await sb.from("profiles").update({ [field]: value }).eq("id", p.id); if (error) toast(error.message); }

    // ───── Calls ─────
    async function callPerson(id) {
      const p = byId(s.people, id); if (!p) return;
      if (s.call) return toast("هناك مكالمة جارية");
      s.call = p; s.callState = "connecting"; s.muted = false;
      caller = window.KocCall(sb, (st) => { s.callState = st; if (["ended", "missed", "rejected", "failed"].includes(st)) setTimeout(() => { if (s.callState === st) s.call = null; }, 2500); });
      try { await caller.start(p.id, s.me.full_name || "ORT · 160"); } catch (e) { s.callState = "failed"; toast("تعذّر بدء المكالمة: " + (e.message || e)); setTimeout(() => (s.call = null), 2000); }
    }
    window.__kocCall = callPerson;
    function hangup() { caller && caller.end("ended"); }
    function toggleMute() { s.muted = !s.muted; caller && caller.mute(s.muted); }
    const CALL_LABEL = { connecting: "جارٍ التجهيز…", ringing: "يرن على هاتف الموظف…", connected: "متصل", ended: "انتهت المكالمة", missed: "لم يرد", rejected: "رفض المكالمة", failed: "تعذّر الاتصال" };

    // ───── Reports & keys ─────
    async function setupKeys() {
      if (s.newPass.length < 10) return toast("عبارة المرور 10 أحرف على الأقل");
      if (s.newPass !== s.newPass2) return toast("عبارتا المرور غير متطابقتين");
      if (s.hasKey && !s.confirmRotate) { s.confirmRotate = true; return; }
      const k = await KocCrypto.createOrgKeys(s.newPass);
      const a = await sb.from("org_public_key").upsert({ id: 1, jwk: k.publicJwk, updated_at: new Date().toISOString() });
      const b = await sb.from("org_private_key").upsert({ id: 1, wrapped: k.wrapped, salt: k.salt, iv: k.iv, updated_at: new Date().toISOString() });
      if (a.error || b.error) return toast("خطأ: " + (a.error || b.error).message);
      s.privKey = k.privateKey; s.newPass = s.newPass2 = ""; s.confirmRotate = false; await loadAll(); toast("أُنشئ مفتاح التشفير. احفظ عبارة المرور في مكان آمن.");
    }
    async function unlockKey() {
      try { s.privKey = await KocCrypto.unlock(s.keyRow, s.pass); s.pass = ""; toast("فُتح المفتاح لهذه الجلسة فقط"); }
      catch (_) { toast("عبارة المرور غير صحيحة"); }
    }
    async function openReport(r) {
      if (!s.privKey) return toast("افتح مفتاح التشفير أولًا");
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
      } catch (e) { toast("تعذّر فك التشفير: المفتاح لا يطابق هذا البلاغ"); }
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
      if (s.session) boot();
      setInterval(() => { s._tick = Date.now(); }, 30000);
    });

    return { s, KINDS, SCOPES, STATUS, CLASSES, REPORT_TYPES, REPORT_STATUS, CALL_LABEL, login, logout, name, fmt, ago,
      newItem, editItem, startDraw, cancelDraw, parseCoords, useMyGps, saveItem, deleteItem, focus, fitAll,
      targets, setKind, reach, launch, closeAlarm, alarmRoster, counts, selAlarmObj, activeAlarms,
      newPerson, savePerson, updatePerson, callPerson, hangup, toggleMute,
      setupKeys, unlockKey, openReport, setReportStatus, kpi, zonesOf, buildingsOf, peopleIn };
  },
}).mount("#app");
