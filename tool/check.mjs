// CI visual + functional check: app (Flutter web build of the same code) and dashboard.
// usage: node tool/check.mjs <appUrl> <dashUrl> <outDir>
import { chromium } from "playwright";
import fs from "node:fs";

const [appUrl, dashUrl, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const errors = [];

// ── App screens ──
const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
const app = await phone.newPage();
app.on("pageerror", e => errors.push("app: " + e.message));
for (const s of ["home", "weather", "operations", "contacts", "news", "duty"]) {
  await app.goto(`${appUrl}?s=${s}`, { waitUntil: "networkidle" });
  await app.waitForTimeout(6000);
  await app.screenshot({ path: `${out}/app-${s}.png` });
}
await app.goto(`${appUrl}?s=home&menu=1`, { waitUntil: "networkidle" });
await app.waitForTimeout(6000);
await app.screenshot({ path: `${out}/app-menu.png` });

// ── Dashboard ──
for (const [name, vp] of [["phone", { width: 412, height: 900 }], ["desktop", { width: 1280, height: 900 }]]) {
  const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: name === "phone" ? 2 : 1 });
  const p = await ctx.newPage();
  p.on("pageerror", e => errors.push(`dash-${name}: ` + e.message));
  await p.goto(dashUrl, { waitUntil: "networkidle" });
  await p.waitForSelector("#loginView:not([hidden])");
  if (name === "desktop") await p.screenshot({ path: `${out}/dash-login.png` });
  await p.fill("#lEmail", process.env.CI_EMAIL);
  await p.fill("#lPass", process.env.CI_PASS);
  await p.click("#lBtn");
  await p.waitForSelector("#appView:not([hidden])", { timeout: 20000 });
  await p.waitForTimeout(2500);
  for (const tab of ["weather", "duty", "news", "ops", "contacts"]) {
    await p.click(`nav.tabs button[data-tab="${tab}"]`);
    await p.waitForTimeout(2500);
    await p.screenshot({ path: `${out}/dash-${name}-${tab}.png`, fullPage: true });
  }
  if (name === "desktop") {
    // write test: add a contact, check it shows, delete it
    await p.fill("#cName", "CI check contact");
    await p.fill("#cPhone", "000");
    await p.click("#cForm button.primary");
    await p.waitForSelector("text=CI check contact", { timeout: 15000 });
    const row = p.locator("#cTable tr", { hasText: "CI check contact" });
    await row.locator("[data-cd]").click();
    await row.locator("[data-cd]").click();
    await p.waitForSelector("text=CI check contact", { state: "detached", timeout: 15000 });
    fs.writeFileSync(`${out}/write-test.txt`, "contact add + delete: OK\n");
  }
  await ctx.close();
}
fs.writeFileSync(`${out}/errors.txt`, errors.join("\n") || "no page errors");
await browser.close();
console.log(errors.length ? errors.join("\n") : "no page errors");
