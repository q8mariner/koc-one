/* ONE · ORT dashboard (ECC-160) — Vue 3 (no build step) + Leaflet + Supabase
   Areas page: Sectors → Zones → Buildings → Employees, each level as boxes with live head-counts,
   multi-select, "alarm all / alarm selected" and "add boundary". */
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
  { k: "areas", t: { ar: "المناطق", en: "Areas" }, tag: { ar: "ECC-160 · كل المواقع", en: "ECC-160 · all sites" }, h: { ar: "القطاعات والموظفون", en: "Sectors and people" }, i: "M4 20V8l8-4 8 4v12M9 20v-6h6v6M4 20h16" },
  { k: "alarms", t: { ar: "الإنذارات", en: "Alarms" }, tag: { ar: "الإنذار والحصر", en: "Alarm & muster" }, h: { ar: "الحوادث ومتابعة الحصر", en: "Incidents and muster" }, i: "M12 3a6 6 0 0 0-6 6v4l-2 3h16l-2-3V9a6 6 0 0 0-6-6zm-2 16a2 2 0 0 0 4 0" },
  { k: "people", t: { ar: "الموظفون", en: "Employees" }, tag: { ar: "الحسابات والهويات", en: "Accounts & IDs" }, h: { ar: "الموظفون وجهات الاتصال", en: "Employees and contacts" }, i: "M16 19v-1a4 4 0 0 0-8 0v1M12 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm7 8v-1a3 3 0 0 0-2-3m-1-9a3 3 0 0 1 0 6" },
  { k: "reports", t: { ar: "بلاغات 160", en: "160 reports" }, tag: { ar: "بلاغات مشفرة", en: "Encrypted reports" }, h: { ar: "بلاغات 160 مع الصور", en: "160 reports with photos" }, i: "M6 3h9l4 4v14H6zM14 3v5h5M9 13h7M9 17h5" },
  { k: "pm", t: { ar: "PM", en: "PM" }, tag: { ar: "Postmaster", en: "Postmaster" }, h: { ar: "الأخبار والفعاليات والتعاميم", en: "News, events and circulars" }, i: "M4 6h16v12H4zM4 7l8 6 8-6" },
  { k: "keys", t: { ar: "التشفير", en: "Encryption" }, tag: { ar: "الأمان", en: "Security" }, h: { ar: "مفتاح تشفير البلاغات", en: "Report encryption key" }, i: "M8 15a4 4 0 1 1 3-6.6L21 8v4h-2v2h-2v2h-3l-2.5-2.4A4 4 0 0 1 8 15zm-1-4h.01" },
];
const POST_KINDS = {
  news: { ar: "خبر", en: "News", c: "#2B4C9B" }, event: { ar: "فعالية", en: "Event", c: "#0E7490" }, circular: { ar: "تعميم", en: "Circular", c: "#B45309" },
  offer: { ar: "عرض", en: "Offer", c: "#2E9E5B" }, announcement: { ar: "إعلان", en: "Announcement", c: "#6D28D9" },
};
const ITEM_TYPES = { sector: { ar: "قطاع", en: "sector" }, zone: { ar: "Zone", en: "zone" }, building: { ar: "مبنى", en: "building" } };
const CLASSES = { unclassified: { ar: "غير مصنفة", en: "Unclassified" }, zone2: { ar: "Zone 2", en: "Zone 2" }, zone1: { ar: "Zone 1", en: "Zone 1" }, zone0: { ar: "Zone 0", en: "Zone 0" } };
const REPORT_TYPES = { fire: { ar: "حريق", en: "Fire" }, leak: { ar: "تسرب غاز/نفط", en: "Gas/oil leak" }, injury: { ar: "إصابة", en: "Injury" },
  road: { ar: "حادث طريق", en: "Road accident" }, suspicious: { ar: "نشاط مشبوه", en: "Suspicious activity" }, hazard: { ar: "خطر سلامة", en: "Safety hazard" }, sos: { ar: "نداء استغاثة", en: "SOS" } };
const REPORT_STATUS = { new: { ar: "جديد", en: "New" }, received: { ar: "استلمه ORT", en: "Received by ORT" }, dispatched: { ar: "أُحيل للفرق", en: "Dispatched" }, closed: { ar: "مغلق", en: "Closed" } };
const CALL_LABEL = { connecting: { ar: "جارٍ التجهيز…", en: "Preparing…" }, ringing: { ar: "يرن على هاتف الموظف…", en: "Ringing the employee’s phone…" },
  connected: { ar: "متصل", en: "Connected" }, ended: { ar: "انتهت المكالمة", en: "Call ended" }, missed: { ar: "لم يرد", en: "No answer" },
  rejected: { ar: "رفض المكالمة", en: "Call declined" }, failed: { ar: "تعذّر الاتصال", en: "Couldn’t connect" } };
// level → selection key, alarm scope of a selected box, item type
const LEVEL = {
  sectors: { scope: "sector", type: "sector" },
  zones: { scope: "zone", type: "zone" },
  buildings: { scope: "building", type: "building" },
  people: { scope: "employee", type: null },
};
const NO_BUILDING = "__none";

let savedLang = "ar";
try { savedLang = localStorage.getItem("one.lang") || "ar"; } catch (_) {}

createApp({
  setup() {
    const s = reactive({
      session: null, me: null, authErr: "", email: "", password: "", busy: false,
      tab: "areas", toast: "", _tick: 0, lang: savedLang,
      sectors: [], zones: [], buildings: [], people: [], alarms: [], acks: [], reports: [],
      // areas drill-down + selection
      path: { sector: null, zone: null, building: null },
      sel: { sectors: [], zones: [], buildings: [], people: [] },
      showMap: true,
      // structure editor
      edit: null, drawing: false,
      // alarm composer (modal) and selected incident
      comp: null, selInc: null,
      // people
      pf: null, pe: null, avatars: {}, verifyCode: "", verifyResult: null, psel: [], pq: "",
      // reports
      privKey: null, pass: "", keyRow: null, hasKey: false, opened: {}, newPass: "", newPass2: "",
      // calls
      call: null, callState: "", muted: false,
      // location-signal losses
      losses: [], clr: null, lossFilter: "all",
      // PM posts
      posts: [], postForm: null, postKind: "all",
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
    const staff = computed(() => s.people.filter((p) => p.role !== "ort"));

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
      try { await sb.rpc("scan_signal"); } catch (_) {}
      await loadAll();
      subscribe();
      await nextTick(); initMap();
    }

    async function loadAll() {
      const [a, b, c, d, e, f, g, k, sl, po] = await Promise.all([
        sb.from("sectors").select("*").order("created_at"),
        sb.from("zones").select("*").order("created_at"),
        sb.from("buildings").select("*").order("created_at"),
        sb.from("profiles").select("*").order("full_name"),
        sb.from("alarms").select("*").order("created_at", { ascending: false }).limit(150),
        sb.from("alarm_acks").select("*"),
        sb.from("reports").select("*").order("created_at", { ascending: false }).limit(200),
        sb.from("org_private_key").select("*").maybeSingle(),
        sb.from("signal_losses").select("*").order("detected_at", { ascending: false }).limit(300),
        sb.from("posts").select("*").order("pinned", { ascending: false }).order("created_at", { ascending: false }).limit(200),
      ]);
      s.sectors = a.data || []; s.zones = b.data || []; s.buildings = c.data || []; s.people = d.data || [];
      s.alarms = e.data || []; s.acks = f.data || []; s.reports = g.data || [];
      s.keyRow = k.data; s.hasKey = !!k.data; s.losses = sl.data || []; s.posts = po.data || [];
      if (!s.selInc) { const act = incidents.value.find((x) => x.active); if (act) s.selInc = act.key; }
      loadAvatars();
    }

    function upsertLocal(arr, row, key = (r) => r.id) { const i = arr.findIndex((x) => key(x) === key(row)); if (i >= 0) arr[i] = row; else arr.unshift(row); }
    function subscribe() {
      sb.channel("ort-live")
        .on("postgres_changes", { event: "*", schema: "public", table: "alarms" }, ({ new: r }) => { r && r.id && upsertLocal(s.alarms, r); })
        .on("postgres_changes", { event: "*", schema: "public", table: "alarm_acks" }, ({ new: r }) => { if (r && r.alarm_id) upsertLocal(s.acks, r, (x) => x.alarm_id + x.user_id); drawPeople(); })
        .on("postgres_changes", { event: "*", schema: "public", table: "profiles" }, ({ new: r }) => { if (r && r.id) { upsertLocal(s.people, r); drawPeople(); } })
        .on("postgres_changes", { event: "*", schema: "public", table: "signal_losses" }, ({ new: r, old }) => {
          if (!r || !r.id) return;
          const was = byId(s.losses, r.id);
          upsertLocal(s.losses, r); drawPeople();
          if (r.status === "open" && (!was || was.status !== "open")) {
            toast(tr("انقطعت إشارة موقع ", "Location signal lost: ") + name("employee", r.user_id) + tr(" أثناء إنذار — تأكد من سلامته", " during an alarm — check they are safe"));
            beep();
          }
        })
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "reports" }, ({ new: r }) => { s.reports.unshift(r); toast(tr("بلاغ جديد وارد إلى 160 — ", "New 160 report — ") + (lt(REPORT_TYPES[r.type]) || r.type)); beep(); })
        .subscribe();
    }
    function beep() { try { const a = new AudioContext(), o = a.createOscillator(); o.frequency.value = 880; o.connect(a.destination); o.start(); o.stop(a.currentTime + 0.25); } catch (_) {} }

    // ───── Areas drill-down ─────
    const level = computed(() => (!s.path.sector ? "sectors" : !s.path.zone ? "zones" : !s.path.building ? "buildings" : "people"));
    const zonesOf = (sid) => s.zones.filter((z) => z.sector_id === sid);
    const buildingsOf = (zid) => s.buildings.filter((b) => b.zone_id === zid);
    const countIn = (field, id) => staff.value.filter((p) => p[field] === id).length;
    const noBuildingCount = computed(() => (s.path.zone ? staff.value.filter((p) => p.cur_zone_id === s.path.zone && !p.cur_building_id).length : 0));
    const peopleHere = computed(() => {
      if (level.value !== "people") return [];
      if (s.path.building === NO_BUILDING) return staff.value.filter((p) => p.cur_zone_id === s.path.zone && !p.cur_building_id);
      return staff.value.filter((p) => p.cur_building_id === s.path.building);
    });
    const levelItems = computed(() => {
      switch (level.value) {
        case "sectors": return s.sectors.map((x) => ({ item: x, count: countIn("cur_sector_id", x.id), field: "cur_sector_id" }));
        case "zones": return zonesOf(s.path.sector).map((x) => ({ item: x, count: countIn("cur_zone_id", x.id), field: "cur_zone_id" }));
        case "buildings": return buildingsOf(s.path.zone).map((x) => ({ item: x, count: countIn("cur_building_id", x.id), field: "cur_building_id" }));
        default: return [];
      }
    });
    const levelIds = computed(() => (level.value === "people" ? peopleHere.value.map((p) => p.id) : levelItems.value.map((x) => x.item.id)));
    const levelTitle = computed(() => ({
      sectors: tr("القطاعات", "Sectors"),
      zones: "Zones · " + name("sector", s.path.sector),
      buildings: tr("المباني · ", "Buildings · ") + name("zone", s.path.zone),
      people: tr("الموظفون داخل ", "Employees in ") + (s.path.building === NO_BUILDING ? tr("الـ Zone خارج المباني", "the zone, outside buildings") : name("building", s.path.building)),
    }[level.value]));
    const addLabel = computed(() => ({ sectors: tr("إضافة قطاع", "Add sector"), zones: tr("إضافة Zone", "Add zone"), buildings: tr("إضافة مبنى", "Add building") }[level.value]));
    const allLabel = computed(() => ({
      sectors: tr("إنذار لجميع القطاعات", "Alarm all sectors"),
      zones: tr("إنذار لكل Zones القطاع", "Alarm all zones in sector"),
      buildings: tr("إنذار لكل مباني الـ Zone", "Alarm all buildings in zone"),
      people: tr("إنذار لكل من في المبنى", "Alarm everyone here"),
    }[level.value]));
    function childInfo(x) {
      if (level.value === "sectors") { const n = zonesOf(x.id).length; return tr(`${n} زون`, `${n} ${n === 1 ? "zone" : "zones"}`); }
      if (level.value === "zones") { const n = buildingsOf(x.id).length; return n + tr(" مبنى", n === 1 ? " building" : " buildings"); }
      if (level.value === "buildings") return x.muster_point ? tr("تجمع: ", "Muster: ") + x.muster_point : "";
      return "";
    }
    function resetSel() { s.sel = { sectors: [], zones: [], buildings: [], people: [] }; }
    function drill(x) {
      if (level.value === "sectors") s.path = { sector: x.id, zone: null, building: null };
      else if (level.value === "zones") s.path = { ...s.path, zone: x.id, building: null };
      else if (level.value === "buildings") s.path = { ...s.path, building: x.id };
      s.sel[level.value] = []; s.edit = null; focusPath();
    }
    function openNoBuilding() { s.path = { ...s.path, building: NO_BUILDING }; s.sel.people = []; focusPath(); }
    function goLevel(lv) {
      if (lv === "sectors") s.path = { sector: null, zone: null, building: null };
      if (lv === "zones") s.path = { ...s.path, zone: null, building: null };
      if (lv === "buildings") s.path = { ...s.path, building: null };
      s.edit = null; focusPath();
    }
    function goTo(type, id) { // from a map click
      if (s.drawing) return;
      s.tab = "areas"; s.edit = null;
      if (type === "sector") s.path = { sector: id, zone: null, building: null };
      if (type === "zone") { const z = byId(s.zones, id); s.path = { sector: z?.sector_id || null, zone: id, building: null }; }
      if (type === "building") { const b = byId(s.buildings, id); const z = b && byId(s.zones, b.zone_id); s.path = { sector: z?.sector_id || null, zone: b?.zone_id || null, building: id }; }
      focusPath();
    }
    const isSel = (id) => s.sel[level.value].includes(id);
    function toggleSel(id) { const a = s.sel[level.value]; const i = a.indexOf(id); if (i >= 0) a.splice(i, 1); else a.push(id); }
    const allSelected = computed(() => levelIds.value.length > 0 && levelIds.value.every((id) => s.sel[level.value].includes(id)));
    function toggleAll() { s.sel[level.value] = allSelected.value ? [] : [...levelIds.value]; }
    const selCount = computed(() => s.sel[level.value].length);

    // live status of people (latest answer to an active incident)
    const activeIds = computed(() => new Set(s.alarms.filter((a) => a.active).map((a) => a.id)));
    function personStatus(uid) {
      if (!activeIds.value.size) return null;
      let best = null;
      for (const k of s.acks) if (k.user_id === uid && activeIds.value.has(k.alarm_id) && (!best || k.updated_at > best.updated_at)) best = k;
      if (best) return best.status;
      const p = byId(s.people, uid);
      return p && s.alarms.some((a) => a.active && inScope(p, a)) ? "none" : null;
    }
    function boxStatus(field, id) {
      if (!activeIds.value.size) return null;
      const r = { safe: 0, help: 0, wait: 0 };
      staff.value.filter((p) => p[field] === id).forEach((p) => {
        const st = personStatus(p.id); if (!st) return;
        if (st === "safe") r.safe++; else if (st === "received" || st === "none") r.wait++; else r.help++;
      });
      return r.safe + r.help + r.wait ? r : null;
    }

    // ───── Map ─────
    function initMap() {
      if (map) return;
      map = L.map("map", { zoomControl: true, attributionControl: true }).setView(C.MAP_CENTER, 12);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: "© OpenStreetMap" }).addTo(map);
      layers = L.layerGroup().addTo(map); peopleLayer = L.layerGroup().addTo(map); drawLayer = L.layerGroup().addTo(map);
      try { new ResizeObserver(() => map && map.invalidateSize()).observe(document.getElementById("map")); } catch (_) {}
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
      const hl = (type, id) => (type === "sector" && s.path.sector === id) || (type === "zone" && s.path.zone === id) || (type === "building" && s.path.building === id);
      s.sectors.forEach((x) => { const p = poly(x.boundary, { color: x.color, weight: hl("sector", x.id) ? 3 : 2, fillOpacity: 0.05, dashArray: "6 6" }); p && p.bindTooltip(tr("قطاع: ", "Sector: ") + x.name).on("click", () => goTo("sector", x.id)).addTo(layers); });
      s.zones.forEach((x) => { const sec = byId(s.sectors, x.sector_id); const p = poly(x.boundary, { color: x.classification === "unclassified" ? (sec?.color || "#2B4C9B") : "#E07B29", weight: hl("zone", x.id) ? 4 : 2, fillOpacity: 0.1 }); p && p.bindTooltip(`${x.name} · ${lt(CLASSES[x.classification])}`).on("click", () => goTo("zone", x.id)).addTo(layers); });
      s.buildings.forEach((x) => { const p = poly(x.boundary, { color: hl("building", x.id) ? "#E5B80B" : "#1F3A7A", weight: hl("building", x.id) ? 3 : 2, fillColor: "#2B4C9B", fillOpacity: 0.18 }); p && p.bindTooltip(tr("مبنى: ", "Building: ") + x.name).on("click", () => goTo("building", x.id)).addTo(layers); });
    }
    // ───── Location-signal losses ─────
    // logged  → normal times: hidden from the map, kept in the log
    // open    → lost ≤1 h before or during an alarm: shown on the map until ORT confirms the employee is safe
    // cleared → confirmed by ORT, back in the log
    const openLossOf = (uid) => s.losses.find((l) => l.user_id === uid && l.status === "open");
    const hiddenLossOf = (uid) => s.losses.find((l) => l.user_id === uid && !l.restored_at && l.status !== "open");
    const openLosses = computed(() => s.losses.filter((l) => l.status === "open").sort((a, b) => (a.lost_at < b.lost_at ? -1 : 1)));
    const lossLog = computed(() => {
      const rows = s.lossFilter === "open" ? openLosses.value : s.lossFilter === "now" ? s.losses.filter((l) => !l.restored_at) : s.losses;
      return [...rows].sort((a, b) => (b.status === "open") - (a.status === "open") || (a.detected_at < b.detected_at ? 1 : -1));
    });
    const lossReason = (l) => (l.reason === "gps_off" ? tr("GPS مغلق", "GPS off") : tr("لا اتصال بالجهاز", "Phone unreachable"));
    const lossArea = (l) => [l.sector_id && name("sector", l.sector_id), l.zone_id && name("zone", l.zone_id), l.building_id && name("building", l.building_id)].filter(Boolean).join(" › ") || "—";
    const lossState = (l) => (l.status === "open" ? [tr("بانتظار التحقق", "Needs check"), "st-bad"] : l.status === "cleared" ? [tr("تم التحقق", "Checked"), "st-ok"] : [tr("عادي · أُخفي من الخريطة", "Normal · hidden from map"), "st-none"]);
    function dur(a, b) { const m = Math.max(0, Math.round((new Date(b || Date.now()) - new Date(a)) / 60000)); void s._tick; return m < 60 ? tr(`${m} د`, `${m} min`) : tr(`${Math.floor(m / 60)} س ${m % 60} د`, `${Math.floor(m / 60)} h ${m % 60} min`); }
    function lossAlarm(l) { const a = l.alarm_id && byId(s.alarms, l.alarm_id); return a ? atitle(a) : ""; }
    function focusLoss(l) {
      s.tab = "areas";
      const p = byId(s.people, l.user_id);
      const pt = !l.restored_at ? [l.last_lat, l.last_lng] : [p?.last_lat, p?.last_lng];
      nextTick(() => { if (map && pt[0]) { map.setView(pt, 17); const mk = lossMarkers[l.id]; mk && mk.openPopup(); document.getElementById("map")?.scrollIntoView({ behavior: "smooth", block: "center" }); } });
    }
    function askClear(l) { if (l) s.clr = { loss: l, note: "", busy: false }; }
    async function saveClear() {
      const c = s.clr; if (!c || c.note.trim().length < 3) return;
      c.busy = true;
      const patch = { status: "cleared", cleared_by: s.me.id, cleared_at: new Date().toISOString(), note: c.note.trim() };
      const { error } = await sb.from("signal_losses").update(patch).eq("id", c.loss.id);
      c.busy = false;
      if (error) return toast(tr("تعذّر الحفظ: ", "Couldn’t save: ") + error.message);
      Object.assign(c.loss, patch); s.clr = null; drawPeople();
      toast(tr("سُجّل التحقق ونُقل إلى سجل انقطاع الإشارة", "Check recorded and moved to the signal log"));
    }
    window.__kocClearLoss = (id) => askClear(byId(s.losses, id));
    let lossMarkers = {};

    const STATUS_COLOR = { safe: "#2E9E5B", received: "#E5B80B", none: "#E5B80B", need_help: "#E07B29", injured: "#C62828", trapped: "#C62828" };
    // Markers are kept and moved in place (live updates every few seconds), so an open popup stays open.
    let pMarkers = {};
    function putMarker(key, make, latlng, html, style) {
      let m = pMarkers[key];
      if (!m) { m = make().bindPopup(html).addTo(peopleLayer); pMarkers[key] = m; }
      else { m.setLatLng(latlng); if (style && m.setStyle) m.setStyle(style); m.setPopupContent(html); }
      return m;
    }
    function drawPeople() {
      if (!peopleLayer) return;
      const seen = new Set(); lossMarkers = {};
      staff.value.forEach((p) => {
        const ol = openLossOf(p.id);
        if (ol) { const m = drawLoss(p, ol); if (m) { seen.add("l" + ol.id); lossMarkers[ol.id] = m; } return; }
        if (!p.last_lat || hiddenLossOf(p.id)) return; // signal lost in normal times → off the map, in the log
        // left every boundary → stays on the map for one minute, then disappears
        const inside = p.cur_sector_id || p.cur_zone_id || p.cur_building_id;
        if (!inside && (!p.last_seen || Date.now() - new Date(p.last_seen) > 60000)) return;
        const st = personStatus(p.id);
        const style = { radius: 7, color: "#ffffff", weight: 2, fillColor: STATUS_COLOR[st] || (p.online ? "#2B4C9B" : "#94A3B8"), fillOpacity: 1 };
        const html = `<b>${esc(p.full_name)}</b><br>${esc(p.employee_no || "")} · ${tr("فصيلة", "Blood")} ${esc(p.blood_type || "—")}<br>${inside ? esc(name("building", p.cur_building_id)) : tr("غادر الحدود", "Left the boundaries")} · ${tr("آخر ظهور", "last seen")} ${ago(p.last_seen)}<br>
            ${st ? tr("الحالة: ", "Status: ") + lt(STATUS[st][0]) + "<br>" : ""}<button class="mini" onclick="window.__kocCall('${p.id}')">${tr("اتصال صوتي", "Voice call")}</button>`;
        const ll = [p.last_lat, p.last_lng];
        putMarker("p" + p.id, () => L.circleMarker(ll, style), ll, html, style);
        seen.add("p" + p.id);
      });
      for (const k of Object.keys(pMarkers)) if (!seen.has(k)) { peopleLayer.removeLayer(pMarkers[k]); delete pMarkers[k]; }
    }
    function drawLoss(p, l) {
      const pt = !l.restored_at ? [l.last_lat ?? p.last_lat, l.last_lng ?? p.last_lng] : [p.last_lat, p.last_lng];
      if (pt[0] == null) return null;
      const icon = L.divIcon({ className: "", html: '<span class="lossmk"><i></i><b>!</b></span>', iconSize: [34, 34], iconAnchor: [17, 17] });
      const back = l.restored_at ? `<br><span style="color:#1F7A45">${tr("عادت الإشارة ", "Signal back ")}${esc(fmt(l.restored_at))}</span>` : "";
      const html = `<b>${esc(p.full_name)}</b> · ${esc(p.employee_no || "")}<br><b style="color:#A11F1F">${tr("انقطاع إشارة الموقع", "Location signal lost")}</b> · ${esc(lossReason(l))}<br>
          ${tr("منذ ", "Since ")}${esc(fmt(l.lost_at))} (${esc(dur(l.lost_at, l.restored_at))})${back}<br>${esc(lossArea(l))}${lossAlarm(l) ? "<br>" + esc(lossAlarm(l)) : ""}<br>
          <button class="mini" onclick="window.__kocCall('${p.id}')">${tr("اتصال صوتي", "Voice call")}</button>
          <button class="mini" style="background:#2E9E5B" onclick="window.__kocClearLoss('${l.id}')">${tr("تأكيد السلامة", "Confirm safe")}</button>`;
      return putMarker("l" + l.id, () => L.marker(pt, { icon, zIndexOffset: 1000 }), pt, html);
    }
    function fitAll() {
      if (!map) return;
      const all = [...s.sectors, ...s.zones, ...s.buildings].filter((x) => x.boundary && x.boundary.length > 2).flatMap((x) => x.boundary);
      if (all.length) map.fitBounds(all, { padding: [30, 30] });
    }
    function focus(item) { if (map && item && item.boundary && item.boundary.length > 2) map.fitBounds(item.boundary, { padding: [40, 40] }); }
    function focusPath() {
      nextTick(() => {
        if (!map) return; map.invalidateSize(); drawAreas();
        const b = s.path.building && s.path.building !== NO_BUILDING ? byId(s.buildings, s.path.building) : null;
        const target = b || byId(s.zones, s.path.zone) || byId(s.sectors, s.path.sector);
        if (target && target.boundary && target.boundary.length > 2) return focus(target);
        // parent without its own boundary: fit to its children
        const kids = level.value === "zones" ? zonesOf(s.path.sector) : level.value === "buildings" ? buildingsOf(s.path.zone) : [];
        const pts = kids.filter((x) => x.boundary && x.boundary.length > 2).flatMap((x) => x.boundary);
        if (pts.length) map.fitBounds(pts, { padding: [30, 30] }); else fitAll();
      });
    }
    const esc = (t) => String(t ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
    watch(() => [s.sectors, s.zones, s.buildings], drawAreas, { deep: true });
    watch(() => [s.acks.length, s.alarms.length], drawPeople);
    watch(() => [s.tab, s.showMap], () => nextTick(() => map && map.invalidateSize()));

    // ───── Structure editor ─────
    function newItem(type, parent = "") {
      s.edit = { type, id: null, name: "", parent, color: "#2B4C9B", classification: "unclassified", code: "", muster_point: "", entry_message: "", boundary: null, coordsText: "" };
      drawLayer && drawLayer.clearLayers();
      revealEditor();
    }
    function newItemHere() {
      const lv = level.value;
      if (lv === "sectors") newItem("sector");
      else if (lv === "zones") newItem("zone", s.path.sector);
      else if (lv === "buildings") newItem("building", s.path.zone);
    }
    function editItem(type, x) {
      s.edit = { type, id: x.id, name: x.name, parent: x.sector_id || x.zone_id || "", color: x.color || "#2B4C9B", classification: x.classification || "unclassified",
        code: x.code || "", muster_point: x.muster_point || "", entry_message: x.entry_message || "", boundary: x.boundary, coordsText: (x.boundary || []).map((p) => p.join(", ")).join("\n") };
      focus(x); drawEditPreview(); revealEditor();
    }
    function revealEditor() { s.showMap = true; nextTick(() => { const el = document.getElementById("editor"); el && el.scrollIntoView({ behavior: "smooth", block: "start" }); }); }
    function startDraw() {
      s.showMap = true; s.drawing = true;
      nextTick(() => {
        map.invalidateSize();
        map.pm.enableDraw("Polygon", { snappable: true, templineStyle: { color: "#E5B80B" }, pathOptions: { color: "#E5B80B" } });
        const m = document.getElementById("map"); if (m && window.innerWidth < 640) m.scrollIntoView({ behavior: "smooth", block: "center" });
      });
    }
    function cancelDraw() { s.drawing = false; map && map.pm.disableDraw(); }
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
    function drawEditPreview() { if (!drawLayer) return; drawLayer.clearLayers(); const p = poly(s.edit?.boundary, { color: "#E5B80B", weight: 3, fillOpacity: 0.2 }); p && p.addTo(drawLayer); }
    function closeEditor() { cancelDraw(); s.edit = null; drawLayer && drawLayer.clearLayers(); }
    async function saveItem() {
      const e = s.edit; if (!e.name.trim()) return toast(tr("اكتب الاسم أولًا", "Enter a name first"));
      const table = { sector: "sectors", zone: "zones", building: "buildings" }[e.type];
      const row = { name: e.name.trim(), boundary: e.boundary, entry_message: e.entry_message || null };
      if (e.type === "sector") row.color = e.color;
      if (e.type === "zone") { if (!e.parent) return toast(tr("اختر القطاع", "Choose a sector")); row.sector_id = e.parent; row.classification = e.classification; }
      if (e.type === "building") { if (!e.parent) return toast(tr("اختر الـ Zone", "Choose a zone")); row.zone_id = e.parent; row.code = e.code || null; row.muster_point = e.muster_point || null; }
      const q = e.id ? sb.from(table).update(row).eq("id", e.id) : sb.from(table).insert(row);
      const { error } = await q; if (error) return toast(tr("خطأ: ", "Error: ") + error.message);
      toast(tr("تم الحفظ", "Saved")); closeEditor(); await loadAll(); focusPath();
    }
    async function deleteItem() {
      const e = s.edit; if (!e.id) return;
      if (!e.confirmDel) { e.confirmDel = true; return; }
      const table = { sector: "sectors", zone: "zones", building: "buildings" }[e.type];
      const { error } = await sb.from(table).delete().eq("id", e.id); if (error) return toast(error.message);
      if (s.path.sector === e.id || s.path.zone === e.id || s.path.building === e.id) goLevel(e.type === "sector" ? "sectors" : e.type === "zone" ? "zones" : "buildings");
      closeEditor(); await loadAll(); toast(tr("تم الحذف", "Deleted"));
    }

    // ───── Alarm targeting ─────
    function inScope(p, a) {
      if (a.scope === "all") return !!(p.cur_sector_id || p.cur_zone_id || p.cur_building_id);
      if (a.scope === "employee") return p.id === a.target_id;
      return p[{ sector: "cur_sector_id", zone: "cur_zone_id", building: "cur_building_id" }[a.scope]] === a.target_id;
    }
    function compose(targets) {
      if (!targets.length) return toast(tr("حدّد هدفًا واحدًا على الأقل", "Select at least one target"));
      s.comp = { targets, kind: "signal2", title: KINDS.signal2.title.ar, title_en: KINDS.signal2.title.en, body: KINDS.signal2.body.ar, body_en: KINDS.signal2.body.en,
        drill: false, second: "", confirm: false, busy: false, showText: false };
    }
    function composeAll() {
      const lv = level.value;
      if (lv === "sectors") return compose([{ scope: "all", id: null }]);
      if (lv === "zones") return compose([{ scope: "sector", id: s.path.sector }]);
      if (lv === "buildings") return compose([{ scope: "zone", id: s.path.zone }]);
      if (s.path.building === NO_BUILDING) return compose(peopleHere.value.map((p) => ({ scope: "employee", id: p.id })));
      return compose([{ scope: "building", id: s.path.building }]);
    }
    function composeSelected() { const lv = level.value; compose(s.sel[lv].map((id) => ({ scope: LEVEL[lv].scope, id }))); }
    function composePeople(ids) { compose(ids.map((id) => ({ scope: "employee", id }))); }
    function setKind(k) { const c = s.comp; c.kind = k; c.title = KINDS[k].title.ar; c.title_en = KINDS[k].title.en; c.body = KINDS[k].body.ar; c.body_en = KINDS[k].body.en; c.confirm = false; }
    const targetLabel = (t) => (t.scope === "all" ? lt(SCOPES.all) : `${lt(SCOPES[t.scope])} · ${name(t.scope, t.id)}`);
    const compReach = computed(() => {
      const c = s.comp; if (!c) return 0;
      return staff.value.filter((p) => c.targets.some((t) => inScope(p, { scope: t.scope, target_id: t.id }))).length;
    });
    const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));
    async function launchComp() {
      const c = s.comp;
      if (!c.title.trim() && !c.title_en.trim()) return toast(tr("اكتب عنوان الإنذار", "Enter the alarm title"));
      if (c.kind !== "message" && (!c.second.trim() || !c.confirm)) return toast(tr("الإطلاق يحتاج تأكيدًا ثنائيًا: اسم الضابط الثاني وتأشير التأكيد", "Launch needs dual confirmation: the second officer’s name and the tick box"));
      c.busy = true;
      const batch = uuid();
      const active = c.kind !== "message" && c.kind !== "signal3";
      const rows = c.targets.map((t) => ({ kind: c.kind, title: c.title.trim() || c.title_en.trim(), body: c.body, title_en: c.title_en.trim() || null, body_en: c.body_en || null,
        scope: t.scope, target_id: t.scope === "all" ? null : t.id, drill: c.drill, created_by: s.me.id, confirmed_by_name: c.second.trim() || null, active, batch_id: batch }));
      const { error } = await sb.from("alarms").insert(rows);
      if (error) { c.busy = false; return toast(tr("تعذّر الإطلاق: ", "Launch failed: ") + error.message); }
      if (c.kind === "signal3") {
        for (const t of c.targets) {
          let q = sb.from("alarms").update({ active: false, closed_at: new Date().toISOString() }).eq("active", true).eq("scope", t.scope);
          q = t.scope === "all" ? q.is("target_id", null) : q.eq("target_id", t.id);
          await q;
        }
      }
      toast(`${tr("أُطلق", "Launched")}: ${c.title_en && s.lang === "en" ? c.title_en : c.title} → ${c.targets.length === 1 ? targetLabel(c.targets[0]) : c.targets.length + tr(" أهداف", " targets")}`);
      s.comp = null; resetSel(); s.psel = [];
      await loadAll();
      if (active) s.selInc = batch;
    }

    // ───── Incidents (alarms grouped by batch) ─────
    const incidents = computed(() => {
      const m = new Map();
      for (const a of s.alarms) { const k = a.batch_id || a.id; if (!m.has(k)) m.set(k, []); m.get(k).push(a); }
      return [...m.entries()].map(([key, alarms]) => {
        const first = alarms[0];
        return { key, alarms, first, kind: first.kind, active: alarms.some((a) => a.active), drill: first.drill, created_at: alarms.reduce((x, a) => (a.created_at < x ? a.created_at : x), first.created_at) };
      }).sort((a, b) => (a.active !== b.active ? (a.active ? -1 : 1) : a.created_at < b.created_at ? 1 : -1));
    });
    const activeIncidents = computed(() => incidents.value.filter((i) => i.active));
    const selIncObj = computed(() => incidents.value.find((i) => i.key === s.selInc));
    function incTargets(inc) {
      if (inc.alarms.length === 1) return targetLabel({ scope: inc.first.scope, id: inc.first.target_id });
      const names = inc.alarms.map((a) => (a.scope === "all" ? lt(SCOPES.all) : name(a.scope, a.target_id)));
      return `${lt(SCOPES[inc.first.scope])} × ${inc.alarms.length}: ` + names.slice(0, 4).join("، ") + (names.length > 4 ? "…" : "");
    }
    function roster(inc) {
      const ids = new Set(inc.alarms.map((a) => a.id));
      const acks = s.acks.filter((k) => ids.has(k.alarm_id));
      const who = new Set([...acks.map((k) => k.user_id), ...staff.value.filter((p) => inc.alarms.some((a) => inScope(p, a))).map((p) => p.id)]);
      const order = { trapped: 0, injured: 1, need_help: 2, none: 3, received: 4, safe: 5 };
      return [...who].map((id) => {
        const p = byId(s.people, id) || { id, full_name: "—" };
        const mine = acks.filter((x) => x.user_id === id).sort((a, b) => (a.updated_at < b.updated_at ? 1 : -1));
        return { p, st: mine[0] ? mine[0].status : "none", k: mine[0] };
      }).sort((x, y) => order[x.st] - order[y.st]);
    }
    function counts(inc) {
      const r = roster(inc), c = { total: r.length, safe: 0, received: 0, need_help: 0, injured: 0, trapped: 0, none: 0 };
      r.forEach((x) => c[x.st]++); c.pct = c.total ? Math.round((c.safe / c.total) * 100) : 0; return c;
    }
    async function closeIncident(inc, allClear) {
      if (allClear) {
        const batch = uuid();
        const rows = inc.alarms.map((a) => ({ kind: "signal3", title: KINDS.signal3.title.ar, body: KINDS.signal3.body.ar, title_en: KINDS.signal3.title.en, body_en: KINDS.signal3.body.en,
          scope: a.scope, target_id: a.target_id, drill: a.drill, created_by: s.me.id, active: false, confirmed_by_name: s.me.full_name, batch_id: batch }));
        await sb.from("alarms").insert(rows);
      }
      await sb.from("alarms").update({ active: false, closed_at: new Date().toISOString() }).in("id", inc.alarms.map((a) => a.id));
      await loadAll(); toast(allClear ? tr("أُرسلت الإشارة 3 · زوال الخطر وأُغلق الحادث", "Signal 3 · All clear sent and the incident closed") : tr("أُغلق الإنذار", "Alarm closed"));
    }

    // ───── People ─────
    const peopleFiltered = computed(() => {
      const q = s.pq.trim().toLowerCase();
      return s.people.filter((p) => !q || [p.full_name, p.employee_no, p.phone, p.job_title, p.department].some((v) => (v || "").toLowerCase().includes(q)));
    });
    function togglePsel(id) { const i = s.psel.indexOf(id); if (i >= 0) s.psel.splice(i, 1); else s.psel.push(id); }
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
      const m = {};
      (data || []).forEach((d, i) => { if (d.signedUrl) m[paths[i]] = d.signedUrl; });
      s.avatars = m;
    }
    const avatar = (p) => (p && p.photo_path ? s.avatars[p.photo_path] : null);
    function editPerson(p) {
      s.tab = "people";
      s.pe = { id: p.id, full_name: p.full_name || "", employee_no: p.employee_no || "", job_title: p.job_title || "", department: p.department || "",
        phone: p.phone || "", blood_type: p.blood_type || "O+", civil_id: p.civil_id || "", active: p.active !== false, role: p.role,
        photo_path: p.photo_path, file: null, preview: avatar(p) };
      nextTick(() => { const el = document.getElementById("id-editor"); el && el.scrollIntoView({ behavior: "smooth", block: "start" }); });
    }
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
    const where = (p) => [name("sector", p.cur_sector_id), name("zone", p.cur_zone_id), name("building", p.cur_building_id)].filter((x) => x !== "—").join(" › ") || tr("خارج الحدود", "Outside all boundaries");

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

    // ───── PM posts ─────
    const postsShown = computed(() => (s.postKind === "all" ? s.posts : s.posts.filter((p) => p.kind === s.postKind)));
    function toLocalInput(iso) { if (!iso) return ""; const d = new Date(iso); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); }
    function newPost() { s.postForm = { id: null, kind: "news", title: "", title_en: "", body: "", body_en: "", event_at: "", location: "", pinned: false }; nextTick(() => document.getElementById("post-form")?.scrollIntoView({ behavior: "smooth", block: "start" })); }
    function editPost(p) { s.postForm = { ...p, title_en: p.title_en || "", body_en: p.body_en || "", location: p.location || "", event_at: toLocalInput(p.event_at) }; nextTick(() => document.getElementById("post-form")?.scrollIntoView({ behavior: "smooth", block: "start" })); }
    async function savePost() {
      const f = s.postForm; if (!f.title.trim() || !f.body.trim()) return toast(tr("العنوان والنص بالعربية مطلوبان", "The Arabic title and text are required"));
      const row = { kind: f.kind, title: f.title.trim(), title_en: f.title_en.trim() || null, body: f.body.trim(), body_en: f.body_en.trim() || null,
        event_at: f.kind === "event" && f.event_at ? new Date(f.event_at).toISOString() : null, location: f.kind === "event" ? (f.location.trim() || null) : null, pinned: !!f.pinned };
      const q = f.id ? sb.from("posts").update(row).eq("id", f.id).select().single() : sb.from("posts").insert({ ...row, created_by: s.me.id }).select().single();
      const { data, error } = await q;
      if (error) return toast(tr("تعذّر الحفظ: ", "Couldn’t save: ") + error.message);
      upsertLocal(s.posts, data); s.postForm = null;
      toast(f.id ? tr("حُدّث المنشور", "Post updated") : tr("نُشر — يظهر الآن في قسم PM في التطبيق", "Published — it now shows in the app’s PM tab"));
    }
    async function deletePost(p) {
      if (!confirm(tr("حذف هذا المنشور من التطبيق؟", "Delete this post from the app?"))) return;
      const { error } = await sb.from("posts").delete().eq("id", p.id);
      if (error) return toast(tr("تعذّر الحذف: ", "Couldn’t delete: ") + error.message);
      s.posts = s.posts.filter((x) => x.id !== p.id);
    }
    const ptitle = (p) => (s.lang === "en" && p.title_en ? p.title_en : p.title);
    const pbody = (p) => (s.lang === "en" && p.body_en ? p.body_en : p.body);

    // ───── KPIs ─────
    const kpi = computed(() => ({
      online: staff.value.filter((p) => p.online).length,
      inside: staff.value.filter((p) => p.cur_sector_id || p.cur_zone_id || p.cur_building_id).length,
      staff: staff.value.length,
      newReports: s.reports.filter((r) => r.status === "new").length,
      active: activeIncidents.value.length,
      lost: openLosses.value.length,
    }));

    onMounted(async () => {
      const { data } = await sb.auth.getSession(); s.session = data.session;
      sb.auth.onAuthStateChange((_e, sess) => { const was = !!s.session; s.session = sess; if (sess && !was) boot(); });
      applyLang();
      if (s.session) boot();
      setInterval(() => { s._tick = Date.now(); }, 30000);
      setInterval(() => { if (s.session && map) drawPeople(); }, 10000); // expire people who left a boundary
    });

    return {
      s, L: lt, tr, atitle, curNav, toggleLang, NAV, ITEM_TYPES, KINDS, SCOPES, STATUS, CLASSES, REPORT_TYPES, REPORT_STATUS, CALL_LABEL, NO_BUILDING,
      login, logout, name, fmt, ago, staff, kpi,
      // areas
      level, levelItems, levelTitle, addLabel, allLabel, childInfo, peopleHere, noBuildingCount, drill, openNoBuilding, goLevel,
      isSel, toggleSel, allSelected, toggleAll, selCount, personStatus, boxStatus, zonesOf, buildingsOf,
      // map + editor
      fitAll, focus, newItem, newItemHere, editItem, startDraw, cancelDraw, parseCoords, useMyGps, saveItem, deleteItem, closeEditor,
      // alarms
      compose, composeAll, composeSelected, composePeople, setKind, targetLabel, compReach, launchComp,
      incidents, activeIncidents, selIncObj, incTargets, roster, counts, closeIncident,
      // people
      peopleFiltered, togglePsel, newPerson, savePerson, avatar, editPerson, pickPhoto, savePersonEdit, verifyId, where,
      callPerson, hangup, toggleMute,
      setupKeys, unlockKey, openReport, setReportStatus,
      // signal losses
      POST_KINDS, postsShown, newPost, editPost, savePost, deletePost, ptitle, pbody,
      openLossOf, hiddenLossOf, openLosses, lossLog, lossReason, lossArea, lossState, lossAlarm, dur, focusLoss, askClear, saveClear,
    };
  },
}).mount("#app");
