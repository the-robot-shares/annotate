/* Landing waitlist: progressive enhancement. The form works without JS (plain
   POST -> thank-you page). With JS it submits via fetch and shows the success
   state in place. Delegated listeners on document so they survive Hologram
   re-renders; state lives on data-* attributes Hologram never diffs. */
(function () {
  "use strict";
  var FORM = "form[data-waitlist]";

  document.addEventListener("submit", function (e) {
    var form = e.target;
    if (!form || !form.matches || !form.matches(FORM)) return;
    e.preventDefault();
    var msg = form.querySelector("[data-waitlist-msg]");
    var wrap = form.closest("[data-waitlist-box]") || form;
    var btn = form.querySelector('button[type="submit"]');
    var data = new FormData(form);
    var interests = data.getAll("interests");
    var payload = {
      email: String(data.get("email") || ""),
      website: String(data.get("website") || "")
    };
    // The landing form asks who you are (about + optional use case); the
    // dashboard plan waitlists still post interests.
    if (interests.length) {
      payload.interests = interests;
    } else {
      payload.about = String(data.get("about") || "");
      payload.use_case = String(data.get("use_case") || "");
    }
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
