/*
 * GA4 opt-in bootstrap (external file: no inline script, no CSP change).
 *
 * Strictest option: gtag.js is NOT requested until the visitor accepts.
 * Before consent there is no googletagmanager / google-analytics network
 * traffic at all (no cookieless pings). Consent Mode v2 defaults are all
 * "denied"; Accept calls gtag('consent','update',{analytics_storage:'granted'})
 * and loads gtag.js. Decline keeps everything denied.
 *
 * The choice persists in localStorage ("annotate_ga_consent", ~12 months).
 * The banner markup is static (rendered by AnalyticsConsent) and only
 * un-hidden here, so Hologram never re-renders it. A "Cookie settings"
 * button is added to the footer to reopen the banner.
 */
(function () {
  var el = document.currentScript;
  var id = el && el.getAttribute("data-ga-id");
  if (!id || !/^G-[A-Z0-9]+$/.test(id)) return;

  var KEY = "annotate_ga_consent";
  var TTL = 365 * 24 * 3600 * 1000;
  var loaded = false;

  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = window.gtag || gtag;

  function read() {
    try {
      var v = JSON.parse(localStorage.getItem(KEY) || "null");
      if (v && (v.v === "granted" || v.v === "denied") && Date.now() - v.t < TTL) return v.v;
    } catch (e) {}
    return null;
  }
  function write(v) {
    try { localStorage.setItem(KEY, JSON.stringify({ v: v, t: Date.now() })); } catch (e) {}
  }

  function load() {
    if (loaded) return;
    loaded = true;
    window["ga-disable-" + id] = false;
    gtag("js", new Date());
    gtag("config", id, { allow_google_signals: false, allow_ad_personalization_signals: false });
    var s = document.createElement("script");
    s.async = true;
    s.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(id);
    document.head.appendChild(s);
  }

  function apply(v) {
    if (v === "granted") {
      gtag("consent", "update", { analytics_storage: "granted" });
      load();
    } else {
      gtag("consent", "update", { analytics_storage: "denied" });
      window["ga-disable-" + id] = true;
    }
  }

  gtag("consent", "default", {
    analytics_storage: "denied",
    ad_storage: "denied",
    ad_user_data: "denied",
    ad_personalization: "denied"
  });

  function banner() { return document.getElementById("ga-consent"); }
  var reopened = false;
  function show() {
    var b = banner();
    if (b) { b.hidden = false; b.removeAttribute("hidden"); }
  }
  function hide() { var b = banner(); if (b) b.hidden = true; }

  function choose(v) { reopened = false; write(v); apply(v); hide(); }

  function addSettingsLink() {
    if (!document.body || document.getElementById("ga-consent-open")) return;
    var btn = document.createElement("button");
    btn.type = "button";
    btn.id = "ga-consent-open";
    btn.className = "ga-consent-open";
    btn.textContent = "Cookie settings";
    var links = document.querySelector(".nd-site-footer__links");
    if (links) links.appendChild(btn);
    else { btn.className += " ga-consent-open--float"; document.body.appendChild(btn); }
  }

  // Hologram hydrates AFTER this script runs and replaces the body's nodes, so
  // per-node listeners are lost. Delegate from `document` (survives any
  // re-render) and re-assert state whenever the DOM changes.
  document.addEventListener("click", function (e) {
    var t = e.target && e.target.closest ? e.target : (e.target && e.target.parentElement);
    if (!t || !t.closest) return;
    var c = t.closest("[data-ga-consent]");
    if (c && c.closest("#ga-consent")) {
      e.preventDefault();
      choose(c.getAttribute("data-ga-consent") === "accept" ? "granted" : "denied");
      return;
    }
    if (t.closest("#ga-consent-open")) { e.preventDefault(); reopened = true; show(); }
  }, true);

  function ensure() {
    addSettingsLink();
    var b = banner();
    if (!b) return;
    var want = reopened || !read();
    if (want && b.hidden) show();
    if (!want && !b.hidden) hide();
  }

  var queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    setTimeout(function () { queued = false; ensure(); }, 50);
  }

  function ready() {
    var stored = read();
    if (stored) apply(stored);
    ensure();
    if (window.MutationObserver) {
      new window.MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ready);
  else ready();
})();
