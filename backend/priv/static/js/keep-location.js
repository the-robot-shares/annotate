/*
 * Hologram's client boot calls history.replaceState(id, null, location.pathname),
 * which silently drops the query string and hash of the landing URL (breaking
 * ?tab=… page identity and #annotate=<thread> deep links). Re-append them to
 * that single boot-time call. One-shot; must load BEFORE the Hologram runtime.
 */
(function () {
  var search = location.search;
  var hash = location.hash;
  if (!search && !hash) return;
  var original = history.replaceState;
  var patched = function (state, title, url) {
    if (history.replaceState === patched) history.replaceState = original;
    if (typeof url === "string" && url === location.pathname) url = url + search + hash;
    return original.call(this, state, title, url);
  };
  history.replaceState = patched;
})();
