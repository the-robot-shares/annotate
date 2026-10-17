/* Landing waitlist: progressive enhancement. The form works without JS (plain
   POST -> thank-you page). With JS it submits via fetch and shows the success
   state in place. Delegated listeners on document so they survive Hologram
   re-renders; state lives on data-* attributes Hologram never diffs. */
(function () {
  "use strict";
  var FORM = "form[data-waitlist]";

  document.addEventListener("click", function (e) {
    var t = e.target && e.target.closest ? e.target.closest("[data-waitlist-interest]") : null;
    if (!t) return;
    var v = t.getAttribute("data-waitlist-interest");
    var box = document.querySelector(FORM + ' input[name="interests"][value="' + v + '"]');
    if (box) box.checked = true;
  });

  document.addEventListener("submit", function (e) {
    var form = e.target;
    if (!form || !form.matches || !form.matches(FORM)) return;
    e.preventDefault();
    var msg = form.querySelector("[data-waitlist-msg]");
    var wrap = form.closest("[data-waitlist-box]") || form;
    var btn = form.querySelector('button[type="submit"]');
    var data = new FormData(form);
    var payload = {
      email: String(data.get("email") || ""),
      website: String(data.get("website") || ""),
      interests: data.getAll("interests")
    };
    function say(text) { if (msg) msg.textContent = text; }
    say("");
    if (btn) btn.disabled = true;
    fetch(form.getAttribute("action"), {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(payload)
    })
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (j) { return { status: r.status, body: j }; });
      })
      .then(function (res) {
        if (res.status === 200 && res.body.ok) {
          wrap.setAttribute("data-state", "done");
          var done = wrap.querySelector("[data-waitlist-done]");
          if (done) { done.removeAttribute("hidden"); done.focus(); }
          form.setAttribute("hidden", "");
        } else if (res.status === 429) {
          say("Too many tries. Wait a minute and try again.");
        } else {
          say((res.body && res.body.message) || "Something went wrong. Try again.");
        }
      })
      .catch(function () { say("Could not reach the server. Try again."); })
      .then(function () { if (btn) btn.disabled = false; });
  });
})();
