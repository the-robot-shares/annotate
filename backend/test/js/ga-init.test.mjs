// node --test test/js/ga-init.test.mjs : behaviour of priv/static/js/ga-init.js with a stub DOM.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const src = fs.readFileSync(new URL("../../priv/static/js/ga-init.js", import.meta.url), "utf8");

function env(stored) {
  const store = new Map(stored ? [["annotate_ga_consent", stored]] : []);
  const appended = [];
  const mk = () => ({ hidden: true, removeAttribute() { this.hidden = false; } });
  let banner = mk();
  const docListeners = {};
  const links = { appendChild(n) { appended.push(n); } };
  const el = { getAttribute: () => "G-TEST123456" };
  const document = {
    currentScript: el, readyState: "complete", head: { appendChild(n) { appended.push(n); } }, body: links,
    documentElement: {},
    getElementById: (i) => (i === "ga-consent" ? banner : null),
    createElement: () => ({ className: "" }),
    querySelector: () => links,
    addEventListener(t, f) { docListeners[t] = f; },
  };
  const window = { dataLayer: [], addEventListener() {}, MutationObserver: class { observe() {} } };
  const ctx = { window, document, Date, JSON, encodeURIComponent, setTimeout: () => {},
    localStorage: { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) } };
  window.window = window;
  vm.runInNewContext(src, ctx);
  const gtagScripts = () => appended.filter((n) => n.src && n.src.includes("googletagmanager.com/gtag/js"));
  // click is delivered to the DOCUMENT (delegation), as a real browser would
  const click = (which) => {
    const hit = (sel) => ({ getAttribute: () => which, closest: (q) => (q === sel || q === "[data-ga-consent]" || q === "#ga-consent" ? hit(sel) : null) });
    docListeners.click({ target: { closest: (q) => (q === "[data-ga-consent]" ? hit(q) : q === "#ga-consent" ? hit(q) : null) }, preventDefault() {} });
  };
  // simulate Hologram hydration replacing the banner node AFTER init
  const rehydrate = () => { banner = mk(); banner.hidden = false; };
  return { get banner() { return banner; }, store, gtagScripts, click, window, rehydrate };
}

test("first visit: banner shown, gtag.js not loaded", () => {
  const e = env();
  assert.equal(e.banner.hidden, false);
  assert.equal(e.gtagScripts().length, 0);
  assert.equal(e.window.dataLayer[0][2].analytics_storage, "denied");
});
test("accept: gtag.js loads, choice persisted, banner hidden", () => {
  const e = env();
  e.click("accept");
  assert.equal(e.gtagScripts().length, 1);
  assert.equal(JSON.parse(e.store.get("annotate_ga_consent")).v, "granted");
  assert.equal(e.banner.hidden, true);
});
test("decline: nothing loads, denial persisted", () => {
  const e = env();
  e.click("decline");
  assert.equal(e.gtagScripts().length, 0);
  assert.equal(JSON.parse(e.store.get("annotate_ga_consent")).v, "denied");
});
test("returning accepted visitor: no banner, gtag loads", () => {
  const e = env(JSON.stringify({ v: "granted", t: Date.now() }));
  assert.equal(e.banner.hidden, true);
  assert.equal(e.gtagScripts().length, 1);
});
test("returning decliner: no banner, no gtag", () => {
  const e = env(JSON.stringify({ v: "denied", t: Date.now() }));
  assert.equal(e.banner.hidden, true);
  assert.equal(e.gtagScripts().length, 0);
});
test("expired choice re-prompts", () => {
  const e = env(JSON.stringify({ v: "granted", t: Date.now() - 400 * 24 * 3600 * 1000 }));
  assert.equal(e.banner.hidden, false);
  assert.equal(e.gtagScripts().length, 0);
});

test("click still works after hydration replaces the banner node (delegation)", () => {
  const e = env();
  e.rehydrate();
  e.click("accept");
  assert.equal(e.gtagScripts().length, 1);
  assert.equal(JSON.parse(e.store.get("annotate_ga_consent")).v, "granted");
});
