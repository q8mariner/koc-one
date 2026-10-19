// Visual + error check of the published dashboard, with dummy data injected (nothing is written to the server).
// Usage: node tool/ui_check.mjs <url> <outdir>
import { chromium } from "playwright";
import fs from "node:fs";

const url = process.argv[2];
const out = process.argv[3] || "ui-shots";
fs.mkdirSync(out, { recursive: true });
const report = { errors: [], shots: [] };

const now = new Date().toISOString();
const box = (lat, lng, d) => [[lat + d, lng - d], [lat + d, lng + d], [lat - d, lng + d], [lat - d, lng - d]];
const DATA = {
  sectors: [
    { id: "s1", name: "قطاع الأحمدي", color: "#2B4C9B", boundary: box(29.07, 48.08, 0.03) },
    { id: "s2", name: "قطاع شمال الكويت", color: "#B45309", boundary: box(29.8, 47.77, 0.08) },
    { id: "s3", name: "قطاع غرب الكويت", color: "#0E7490", boundary: null },
  ],
  zones: [
    { id: "z1", sector_id: "s1", name: "Zone 1 · المجمع الإداري", classification: "unclassified", boundary: box(29.075, 48.078, 0.008) },
    { id: "z2", sector_id: "s1", name: "Zone 2", classification: "zone2", boundary: box(29.06, 48.09, 0.006) },
    { id: "z3", sector_id: "s1", name: "Zone 3", classification: "zone1", boundary: null },
  ],
  buildings: [
    { id: "b1", zone_id: "z1", name: "المبنى الإداري B", muster_point: "MP-3", boundary: box(29.075, 48.0775, 0.0012) },
    { id: "b2", zone_id: "z1", name: "مبنى الخدمات", muster_point: "MP-1", boundary: box(29.078, 48.081, 0.001) },
  ],
};
const people = [];
for (let i = 0; i < 9; i++) people.push({ id: "p" + i, full_name: ["سارة الرشيدي", "محمد الهاجري", "فهد العجمي", "نورة المطيري", "Rajesh Kumar", "علي الظفيري", "منى الكندري", "خالد العنزي", "Anna Petrova"][i],
  role: "employee", employee_no: String(104870 + i), blood_type: ["O+", "A-", "B+", "O-", "AB+", "A+", "O+", "B-", "A+"][i], phone: "+965 9000 00" + i, online: i % 3 !== 0,
  job_title: i % 2 ? "مهندس عمليات" : "فني سلامة", cur_sector_id: i < 7 ? "s1" : "s2", cur_zone_id: i < 6 ? "z1" : i < 7 ? "z2" : null, cur_building_id: i < 4 ? "b1" : i < 5 ? "b2" : null,
  last_lat: 29.075 + i * 0.0003, last_lng: 48.0775, last_seen: now, active: true });
people.push({ id: "me", full_name: "ORT Officer", role: "ort", employee_no: "83784" });
DATA.people = people;
DATA.alarms = [{ id: "a1", kind: "signal2", title: "الإشارة 2 — إخلاء", title_en: "Signal 2 — Evacuate", body: "1. أخلِ المنطقة", scope: "building", target_id: "b1", active: true, drill: true, created_at: now, created_by: "me", batch_id: "bt1" },
  { id: "a2", kind: "signal2", title: "الإشارة 2 — إخلاء", title_en: "Signal 2 — Evacuate", body: "1. أخلِ المنطقة", scope: "building", target_id: "b2", active: true, drill: true, created_at: now, created_by: "me", batch_id: "bt1" }];
DATA.acks = [{ alarm_id: "a1", user_id: "p0", status: "safe", updated_at: now }, { alarm_id: "a1", user_id: "p1", status: "trapped", updated_at: now }, { alarm_id: "a1", user_id: "p2", status: "received", updated_at: now }];
DATA.reports = [{ id: "r1", type: "fire", user_id: "p1", status: "new", created_at: now, photo_paths: ["x"], lat: 29.07, lng: 48.08 }];

async function run(name, viewport, lang, steps) {
  const ctx = await chromium.launch().then((b) => b.newContext({ viewport, deviceScaleFactor: 1, isMobile: viewport.width < 900, hasTouch: viewport.width < 900 }));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => report.errors.push(`${name}: pageerror ${e.message}`));
  page.on("console", (m) => { if (m.type() === "error" && !/favicon|ERR_|Failed to load resource/.test(m.text())) report.errors.push(`${name}: console ${m.text()}`); });
  await page.addInitScript((l) => { try { localStorage.setItem("one.lang", l); } catch (_) {} }, lang);
  await page.goto(url + "?ui=" + Date.now(), { waitUntil: "networkidle" });
  await page.waitForFunction(() => document.querySelector("#app")?.__vue_app__);
  await page.evaluate((D) => {
    const app = document.querySelector("#app").__vue_app__;
    app.config.errorHandler = (e) => { (window.__vueErrors ||= []).push(String(e && e.message || e)); };
    const s = app._container._vnode.component.setupState.s;
    Object.assign(s, D);
    s.session = { user: { id: "me" } };
    s.me = D.people.find((p) => p.id === "me");
    s.selInc = "bt1";
  }, DATA);
  await page.waitForTimeout(400);
  for (const [label, fn] of steps) {
    await page.evaluate(fn);
    await page.waitForTimeout(450);
    const file = `${out}/${name}-${label}.png`;
    await page.screenshot({ path: file, fullPage: true });
    // horizontal overflow check
    const ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    if (ov > 1) report.errors.push(`${name}-${label}: horizontal overflow ${ov}px`);
    report.shots.push(file);
  }
  const ve = await page.evaluate(() => window.__vueErrors || []);
  ve.forEach((e) => report.errors.push(`${name}: vue ${e}`));
  await ctx.browser().close();
}

const st = () => document.querySelector("#app").__vue_app__._container._vnode.component.setupState;
const S = (code) => new Function(`const st=document.querySelector("#app").__vue_app__._container._vnode.component.setupState; const s=st.s; ${code}`);
const steps = [
  ["1-sectors", S(`s.tab='areas'; s.path={sector:null,zone:null,building:null}; s.sel.sectors=['s1'];`)],
  ["2-zones", S(`s.path={sector:'s1',zone:null,building:null}; s.sel.zones=[];`)],
  ["3-buildings", S(`s.path={sector:'s1',zone:'z1',building:null};`)],
  ["4-people", S(`s.path={sector:'s1',zone:'z1',building:'b1'}; s.sel.people=['p0','p2'];`)],
  ["5-composer", S(`st.composeSelected();`)],
  ["6-editor", S(`s.comp=null; s.path={sector:'s1',zone:'z1',building:null}; st.newItemHere();`)],
  ["7-alarms", S(`s.edit=null; s.tab='alarms';`)],
  ["8-people", S(`s.tab='people'; s.psel=['p3'];`)],
  ["9-reports", S(`s.tab='reports';`)],
];
await run("phone-ar", { width: 390, height: 844 }, "ar", steps);
await run("phone-en", { width: 390, height: 844 }, "en", steps.slice(0, 5));
await run("desktop-ar", { width: 1440, height: 900 }, "ar", [steps[0], steps[1], steps[3], steps[4], steps[6]]);
fs.writeFileSync(`${out}/report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report.errors, null, 2));
