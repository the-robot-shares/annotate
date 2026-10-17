// node --test test/js/ga-init.test.mjs : behaviour of priv/static/js/ga-init.js with a stub DOM.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const src = fs.readFileSync(new URL("../../priv/static/js/ga-init.js", import.meta.url), "utf8");

function env(stored) {
  const store = new Map(stored ? [["annotate_ga_consent", stored]] : []);
  const appended = [];
  const banner = { hidden: true, listeners: {}, removeAttribute() { this.hidden = false; },
    addEventListener(t, f) { this.listeners[t] = f; } };
  const links = { appendChild(n) { appended.push(n); } };
  const el = { getAttribute: () => "G-TEST123456" };
  const document = {
    currentScript: el, readyState: "complete", head: { appendChild(n) { appended.push(n); } }, body: links,
    getElementById: (i) => (i === "ga-consent" ? banner : null),
    createElement: () => ({ addEventListener() {}, className: "" }),
    querySelector: () => links, addEventListener() {},
  };
  const window = { dataLayer: [], addEventListener() {} };
  const ctx = { window, document, Date, JSON, encodeURIComponent, setTimeout: () => {},
    localStorage: { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) } };
  window.window = window;
  vm.runInNewContext(src, ctx);
  const gtagScripts = () => appended.filter((n) => n.src && n.src.includes("googletagmanager.com/gtag/js"));
  const click = (which) => banner.listeners.click({ target: { closest: () => ({ getAttribute: () => which }) } });
  return { banner, store, gtagScripts, click, window };
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
