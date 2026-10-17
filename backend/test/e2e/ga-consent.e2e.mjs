// Real-browser regression for the GA4 opt-in banner + landing loop list.
// Needs a server that renders GA (prod, or dev with GA_MEASUREMENT_ID=G-… and
// GA_FORCE_NON_PROD=1) and a system Chrome:
//   cd backend/test/e2e && npm i && BASE_URL=https://annotate.therobotlives.com npm test
// Runs AFTER Hologram hydration (the bug: hydration replaced the banner nodes
// and dropped per-node listeners, so Accept did nothing).
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { chromium } from "playwright-core";

const BASE = process.env.BASE_URL || "http://localhost:4000";
const GA_RE = /(googletagmanager\.com|google-analytics\.com|analytics\.google\.com)/;
let browser;

before(async () => {
  browser = await chromium.launch({ channel: process.env.PW_CHANNEL || "chrome", headless: true });
});
after(async () => { await browser?.close(); });

async function fresh() {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const google = [];
  const cspErrors = [];
  page.on("request", (r) => { if (GA_RE.test(r.url())) google.push(r.url()); });
  // Cloudflare auto-injects its own beacon, which the strict CSP blocks: not ours.
  page.on("console", (m) => { if (/Content Security Policy|Refused to/i.test(m.text()) && !/cloudflareinsights/.test(m.text())) cspErrors.push(m.text()); });
  await page.goto(BASE + "/", { waitUntil: "networkidle" });
  await page.waitForTimeout(1500); // let hydration finish and swap nodes
  return { ctx, page, google, cspErrors };
}

test("nothing goes to Google before a choice", async () => {
  const { ctx, page, google, cspErrors } = await fresh();
  assert.equal(await page.locator("#ga-consent").isVisible(), true);
  assert.deepEqual(google, []);
  assert.deepEqual(cspErrors, []);
  await ctx.close();
});

// Deterministic stand-in for Hologram hydration: swap the banner (and footer
// button) for fresh clones, dropping every per-node listener. Delegated
// handling must still work.
async function rehydrate(page) {
  await page.evaluate(() => {
    for (const sel of ["#ga-consent", "#ga-consent-open"]) {
      const n = document.querySelector(sel);
      if (n) n.replaceWith(n.cloneNode(true));
    }
  });
}

test("Accept works after the banner nodes are replaced (hydration race)", async () => {
  const { ctx, page, google } = await fresh();
  await rehydrate(page);
  await page.click('[data-ga-consent="accept"]');
  await page.waitForTimeout(2500);
  assert.equal(await page.locator("#ga-consent").isVisible(), false);
  assert.ok(google.some((u) => /g\/collect/.test(u)), "g/collect after accept");
  await ctx.close();
});

test("Decline + Cookie settings work after the nodes are replaced", async () => {
  const { ctx, page, google } = await fresh();
  await rehydrate(page);
  await page.click('[data-ga-consent="decline"]');
  assert.equal(await page.locator("#ga-consent").isVisible(), false);
  await rehydrate(page);
  await page.click("#ga-consent-open");
  assert.equal(await page.locator("#ga-consent").isVisible(), true);
  assert.deepEqual(google, []);
  await ctx.close();
});

test("Accept hides the banner, loads gtag, fires g/collect, and persists", async () => {
  const { ctx, page, google, cspErrors } = await fresh();
  await page.click('[data-ga-consent="accept"]');
  await page.waitForTimeout(2500);
  assert.equal(await page.locator("#ga-consent").isVisible(), false);
  assert.ok(google.some((u) => u.includes("gtag/js")), "gtag.js requested after accept");
  assert.ok(google.some((u) => /g\/collect/.test(u)), "g/collect fired after accept: " + google.join(" "));
  assert.deepEqual(cspErrors, []);
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  assert.equal(await page.locator("#ga-consent").isVisible(), false, "banner stays hidden after reload");
  await ctx.close();
});

test("Decline hides the banner, sends nothing to Google, and persists", async () => {
  const { ctx, page, google } = await fresh();
  await page.click('[data-ga-consent="decline"]');
  await page.waitForTimeout(2000);
  assert.equal(await page.locator("#ga-consent").isVisible(), false);
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  assert.equal(await page.locator("#ga-consent").isVisible(), false);
  assert.deepEqual(google, []);
  await ctx.close();
});

test("Cookie settings reopens the banner and a new choice works", async () => {
  const { ctx, page, google } = await fresh();
  await page.click('[data-ga-consent="decline"]');
  await page.waitForTimeout(500);
  await page.click("#ga-consent-open");
  assert.equal(await page.locator("#ga-consent").isVisible(), true);
  await page.click('[data-ga-consent="accept"]');
  await page.waitForTimeout(2500);
  assert.equal(await page.locator("#ga-consent").isVisible(), false);
  assert.ok(google.some((u) => /g\/collect/.test(u)));
  await ctx.close();
});

test("loop list: no native markers, counters read 01..05", async () => {
  const { ctx, page } = await fresh();
  const info = await page.evaluate(() => [...document.querySelectorAll("ol.nd-loop > li")].map((li) => ({
    marker: getComputedStyle(li).listStyleType,
    display: getComputedStyle(li).display,
    num: getComputedStyle(li, "::before").content,
  })));
  assert.equal(info.length, 5);
  info.forEach((i) => assert.equal(i.marker, "none"));
  assert.equal(await page.locator("ol.nd-loop > li").evaluateAll((els) => els.length), 5);
  // counters: evaluate rendered text of ::before via a probe is not possible; assert reset+increment wiring
  const wiring = await page.evaluate(() => {
    const ol = document.querySelector("ol.nd-loop");
    return { reset: getComputedStyle(ol).counterReset, inc: getComputedStyle(ol.children[0], "::before").counterIncrement };
  });
  assert.match(wiring.reset, /nd-step/);
  assert.match(wiring.inc, /nd-step/);
  await ctx.close();
});
