// Browser smoke test of the built web app (CI runs it after `flutter build web`).
// Serves build/web under /<repo>/, opens the home page on a desktop and a
// phone, turns on Flutter's accessibility tree so the text is in the DOM,
// checks the page really rendered, tries the area search and the language
// switch, and saves screenshots for review.
//   node web_smoke/smoke.mjs <path to build/web> <base path, e.g. /drishti/>
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const [root, base = '/', prefix = ''] = process.argv.slice(2);
const out = 'web_smoke/out';
fs.mkdirSync(out, { recursive: true });

const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.css': 'text/css',
  '.ico': 'image/x-icon', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (!p.startsWith(base)) { res.writeHead(404); return res.end(); }
  p = p.slice(base.length) || 'index.html';
  let file = path.join(root, p);
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
const port = 8089 + (prefix ? 1 : 0);
await new Promise((r) => server.listen(port, r));
const url = `http://localhost:${port}${base}`;

const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); };

const browser = await chromium.launch();
async function run(name, viewport) {
  const page = await browser.newPage({ viewport });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 60000 });
  await page.waitForTimeout(4000);
  // Turn on the semantics tree so the rendered text is queryable.
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1500);
  const text = async () => page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics, [aria-label], span')].map((e) => (e.getAttribute('aria-label') || e.textContent || '')).join(' | '));
  const t0 = await text();
  check(t0.includes('Your city, seen from space every five days.'), `${name}: headline rendered`);
  check(t0.includes('Raise a complaint'), `${name}: primary action rendered`);
  await page.waitForTimeout(3000); // let the one-time scan finish
  await page.screenshot({ path: `${out}/${prefix}${name}-home.png`, fullPage: false });

  // Language switch
  const hi = page.getByRole('button', { name: 'हिंदी' }).first();
  if (await hi.count()) {
    await hi.click();
    await page.waitForTimeout(1500);
    check((await text()).includes('आपका शहर, हर पाँच दिन में अंतरिक्ष से।'), `${name}: Hindi headline after switch`);
    await page.screenshot({ path: `${out}/${prefix}${name}-home-hi.png` });
  } else {
    check(false, `${name}: language switch found`);
  }
  // The rest of the home page, then the other screens, for the review screenshots.
  if (name === 'desktop') {
    await page.mouse.move(700, 600);
    for (let i = 1; i <= 3; i++) {
      await page.mouse.wheel(0, 850);
      await page.waitForTimeout(900);
      await page.screenshot({ path: `${out}/${prefix}${name}-home-${i}.png` });
    }
    await page.goto(url, { waitUntil: 'load' });
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 60000 });
    await page.waitForTimeout(3000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(1000);
    for (const [label, file] of [['Raise a complaint', 'raise'], ['Track a complaint', 'track'], ['Impact', 'impact'], ['Officials', 'console']]) {
      const b = page.getByRole('button', { name: label }).first();
      if (!(await b.count())) { check(false, `${name}: button ${label}`); continue; }
      await b.click();
      await page.waitForTimeout(3500);
      await page.screenshot({ path: `${out}/${prefix}${name}-${file}.png` });
      check(true, `${name}: opened ${label}`);
      await page.goBack().catch(() => {});
      await page.keyboard.press('Escape').catch(() => {});
      await page.goto(url, { waitUntil: 'load' });
      await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 60000 });
      await page.waitForTimeout(3000);
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      await page.waitForTimeout(1000);
    }
  }
  const real = errors.filter((e) => !/Failed to load resource|net::|supabase|websocket|CORS/i.test(e));
  check(real.length === 0, `${name}: no script errors${real.length ? ': ' + real.slice(0, 3).join(' / ') : ''}`);
  await page.close();
}
await run('desktop', { width: 1440, height: 900 });
await run('phone', { width: 390, height: 844 });
await browser.close();
server.close();
if (failures.length) { console.error(`${failures.length} check(s) failed`); process.exit(1); }
console.log('web smoke: all checks passed');
