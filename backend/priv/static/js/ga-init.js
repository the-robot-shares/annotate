/*
 * GA4 bootstrap (external so the marketing CSP needs no extra inline script).
 * Read the measurement id from this script tag's data-ga-id. Consent Mode v2
 * defaults: analytics granted, advertising signals denied. GA4 does not store
 * IP addresses.
 */
(function () {
  var el = document.currentScript;
  var id = el && el.getAttribute("data-ga-id");
  if (!id || !/^G-[A-Z0-9]+$/.test(id)) return;
  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = gtag;
  gtag("consent", "default", {
    analytics_storage: "granted",
    ad_storage: "denied",
    ad_user_data: "denied",
    ad_personalization: "denied"
  });
  gtag("js", new Date());
  gtag("config", id, { allow_google_signals: false, allow_ad_personalization_signals: false });
})();
