# annotate — Landing Copy v2

Voice profile: `agency_devs` (primary; full card in `marketing-overview.yaml`,
root of this repo). Section shifts noted inline — `product_teams` voice on
review-facing copy, `agent_first_teams` voice on the MCP section.

Status: copy only — structure/design stay with the UX/design lane. Claims are
limited to shipped behavior; every section carries an `Evidence:` line mapping
copy to code/docs in this worktree. Planned features are labeled **Planned**
wherever they appear.

---

## 0. Primary audience — chosen + rationale

**Primary: `agency_devs` — freelance/agency developers shipping client sites.**

Rationale:

1. **They install.** The product's first conversion is pasting a script tag —
   a developer's act, not a team's purchase decision.
2. **They own the pain.** Client feedback with lost context ("the button near
   the top") is their daily tax; element-anchored threads remove it directly.
3. **The MCP loop is their multiplier, not a separate pitch.** The same
   person who embeds the widget runs Claude Code/Codex; the agent story
   upgrades the primary story instead of splitting it.
4. `product_teams` remains a first-class secondary (review-round copy speaks
   to them); `agent_first_teams` gets a dedicated section (§ 8) in their own
   voice rather than the whole page.

Message hierarchy (canonical, mirrors `marketing-overview.yaml`):

| Level | Copy |
|---|---|
| Tagline | Feedback that points at the thing. |
| One-liner | One script tag pins threaded comments to the exact element or text they're about — then triage in a dashboard, over an API, or by your AI agents. |
| Benefit pillars | Anchors that survive · Triage where you work · Agents over MCP |
| Proof | The live widget on this page + shipped-only claims. No numbers/testimonials exist yet — slots stay EMPTY (§ 9). |

---

## 1. Nav

Wordmark: `annotate`

Links (trim from 9 to 6 — Privacy/Terms/MCP reference move to footer; the
MCP section anchor keeps the agent story one click away):

| Label | Target |
|---|---|
| How it works | `#how-it-works` |
| The loop | `#the-loop` |
| Features | `#features` |
| For agents | `#agents` |
| Pricing | `/pricing` |
| FAQ | `#faq` |

Nav CTA: `Try it on this page` (kept — it is the product demo).
Sign-in control: GitHub button, unchanged component.

Rationale for the trim: the current 9-link nav reads as a sitemap; six
anchors keep the demo CTA visually dominant. `Rationale: current nav in
landing_page.ex lines 37–45.`
Evidence: every target exists today (`landing_page.ex`, `mcp_server_page.ex`,
`/pricing`, `pricing_page.ex`).

---

## 2. Hero

**Voice profile: agency_devs**

Eyebrow: `annotate`

### Headline (primary)

> **Feedback that points at the thing.**

Passes the 3-second test (names the mechanic, not the category), cannot
describe a page-level comment plug-in unchanged, and now matches the SEO
title — one message, no split. 7 words.

### Alternates

- **A — loop-forward** (use if the page leans agent-first, e.g. after the MCP
  launch post): > **From a comment on the page to a fix in the repo.**
  (current live headline; keep in rotation — it is the honest arc and the
  first candidate hero A/B arm)
- **B — client-pain-forward** (use in agency-channel campaigns):
  > **Client feedback that names the button — not "the button near the top".**

### Subhead

> annotate pins threaded comments to the exact element or text they're about.
> Triage them in your dashboard, over the REST API — or hand the inbox to
> your AI agent over MCP.

### CTAs

- Primary: `Try it on this page`
- Secondary: `Start free` (anchors to § 10)
- Caption: `No signup to look around. To post or install: create an account, add your site, paste your tag.`

Evidence: pick-mode CTA arms the real widget (`landing_page.ex` `try_it`
action); public read + sign-in-to-post verified (FAQ + `sites.ex` public_read
default, anonymous off on the demo site); MCP triage shipped (`docs/MCP.md`).

---

## 3. Demo — "Try it on this page" (microcopy for the live widget)

**Voice profile: agency_devs.** Written for someone actually clicking through.

| Slot | Copy |
|---|---|
| After pick-mode arms | `Pick anything on this page — a button, a chart, a sentence. The dashed ring is your target.` |
| Composer placeholder | `Say what's wrong — or right. The element you picked is quoted above.` |
| Attach hint | `Attach a file, or crop the page and draw on it. Uploads run while you type.` |
| Sign-in gate (rail) | `Sign in to post — reading never needs an account.` |
| Empty rail | `No comments on this page yet. Select any text or element to start one.` |
| After posting | `On the rail. The site's team sees it the moment it lands — replies and resolutions arrive live.` |
| Exit pick mode | `Done pointing? Exit from the pill — the page goes back to normal.` |
| Agent handoff (post-demo line) | `Now let your agent close the loop: claude mcp add --transport http annotate https://annotate.therobotlives.com/mcp` |

Rules for the design lane: the hint line renders in the rail, never as a
modal; the widget never intercepts normal page interactions (IA rule); the
exit affordance stays visible while pick mode is armed.

Evidence: pick mode + dashed ring (7-step frames 1–2, live page); composer
quotes the pick (frame 2); screenshot crop + markup (frame 3–4, feature
illustration); live updates (websocket, `comments.ex` Realtime alias);
sign-in to post / public read (FAQ, EMBED-AUTH); exit affordance
(`design/landing/IA.md` dogfood states); MCP one-liner (`docs/MCP.md`
Connect).

---

## 4. How it works

**Voice profile: agency_devs**

Section intro:

> Three steps from "no feedback tool" to "feedback that closes itself".
> Everything below ships in the script today.

1. **Drop in one script tag.**
   Paste two lines before `</body>` — a loader and the `noizu-page-comments`
   element with your site slug. Pick the always-newest loader or pin an
   exact version that never changes.
2. **Visitors pick the exact spot.**
   A click marks the element; a highlight marks the text. The thread anchors
   with fallback strategies — id, CSS, XPath, text quote, position — so it
   re-finds its spot after redesigns.
3. **Triage where you already work.**
   The dashboard inbox for humans, a JSON REST API with live events for your
   stack, MCP for your agents. Same threads, same anchors, all three.

(Note for the design lane: the existing 7-frame gallery under "How it works"
stays — its captions are accurate; optional tightening listed in § 12.)

Evidence: embed snippet (EMBED-AUTH § 0; `widget_cdn.ex` latest/pinned);
anchor strategies + resolution order (docs/ANCHORS.md); dashboard + REST +
MCP surfaces (README, docs/MCP.md, API docs).

---

## 5. The loop

**Voice profile: agency_devs** (chips carry the honesty)

Section heading: `Comment. Triage. Fix. Resolve.` (drops "Ticket." from the
current heading — a planned step must not headline the section; it keeps its
chip below.)

| Step | Copy | Chip |
|---|---|---|
| 1 Comment on the page | A visitor selects the button, the sentence, the price row. The thread pins to that element — not to a screenshot of it. | Shipped |
| 2 Triage in the dashboard | Open the inbox: filter open and resolved, reply as the site team, resolve the noise, reopen what isn't. Updates arrive live. | Shipped |
| 3 Ticket in your tracker | Push a thread to Jira, Notion, ClickUp, Asana, or The Robot Plans — anchor and page context attached. | Planned |
| 4 Agents investigate and patch | Connect Claude Code or any MCP client: it lists open threads, pulls the anchor, reproduces, patches your repo, replies on the thread. | Shipped |
| 5 Resolve back on the page | The thread closes where it started, and anyone on the page sees it settled. | Shipped |

Footnote: `Steps 1, 2, 4 and 5 work today (step 4 over MCP). Step 3 is
planned — the REST API already carries everything it needs.`

Evidence: unchanged from shipped loop section (`landing_page.ex` §the-loop),
which the .ex lane already chips Shipped/Planned; agent tools verified in
docs/MCP.md tools table.

---

## 6. Features — "What ships in the script"

**Voice profile: agency_devs** (tiles are claims; all verified)

| Tile | Copy |
|---|---|
| Anchor that survives | id, CSS, XPath, text quote, and position strategies with fallbacks; the thread re-finds its element when the DOM shifts. Deep links reopen the exact spot. |
| Rail and ring | The rail floats beside the element and follows scroll. Open a comment and the element rings on the page. |
| Threads with a lifecycle | Nested replies, resolve, reopen. Edit and delete stay with the author; moderation stays with the site owner. |
| Screenshots and attachments | Crop the page and draw boxes, arrows, freehand, text, and blur. Attach files to any comment; failed uploads retry on their own. |
| Live updates | New comments, replies, and resolutions arrive over a websocket — no refresh. |
| Rules, roles, sign-in | Per-site rules: anonymous opt-in, guest names, who can read. GitHub sign-in for owners; visitors sign in through your identity provider — or your site vouches for them, no popup at all. |

Evidence: ANCHORS.md (strategies, repair, deep links, orphans); rail/ring
(frames 5–6); moderation split (README Phase 1); attachments + retry
(README uploads; frame 4); Realtime websocket (`comments.ex`); per-site
policy keys (`sites.ex` security keys incl. `allow_anonymous`,
`trust_host_roles`, `read_visibility`); popup broker + host-assert
(docs/EMBED-AUTH.md).

---

## 7. Pricing teaser (landing section)

**Voice profile: agency_devs — strictly matter-of-fact**

Heading: `Unlimited comments. Plans sized to your stack.`

- **Start — $0.99/mo** · 3 sites, 3 users, 100 MB attachments. Unlimited comments.
- **Standard — $3.99/mo** · 10 sites, 3 users, 1 GB attachments. Unlimited comments.
- **Team — $9.99/mo** · Unlimited sites, 5 users, 10 GB (+$0.99 per extra user or GB). Unlimited comments.

Footnote: `Every account starts with a 14-day free trial — no card to start.
Full pricing and the coming agent add-on: /pricing.`

Evidence: `pricing_page.ex` moduledoc + rendered tiers (Start/Standard/Team,
trial FAQ, "no card required to try"); agent add-on is waitlist-only
("coming soon", not purchasable) — never phrased as buyable.
NOTE (open question for the coordinator): `seo.ex` moduledoc and `llms.txt`
still say "no pricing published" — stale against shipped `/pricing`; flagged
in `marketing-overview.yaml` open_questions for the .ex lane.

---

## 8. For agents (MCP)

**Voice profile: agent_first_teams** — precise, zero salesmanship.

Heading: `Your agents read the feedback too.`

Intro:

> annotate ships a remote MCP server over Streamable HTTP. Connect Claude
> Code, Claude Desktop or claude.ai, Cursor, VS Code, or Codex. An agent
> signs in as you — OAuth in your browser, no API keys — and works your
> sites' threads: query what's open, investigate the anchored element,
> patch, reply, resolve.

### The agent loop

1. Query open issues — `list_threads`
2. Pull one with its anchor, page context, attachments — `get_thread`
3. Triage: reproduce what the visitor saw, find the element in your repo — the anchor names the id, CSS, XPath, and text quote
4. Patch
5. Reply as the site team — `reply_to_thread`
6. Resolve — `resolve_thread`

Also exposed: `list_sites`, `get_site_config`, `reopen_thread`,
`delete_comment`, resources for sites and threads, and two prompts —
`triage_open_threads` and `investigate_thread`. Full reference: `/mcp-server`.

### Install snippet (the CTA)

Label: `Claude Code`

```
claude mcp add --transport http annotate https://annotate.therobotlives.com/mcp
```

One-line caption: `Then /mcp → annotate → Authenticate. The client opens a
browser; you pick what it may do.`

(Other clients keep the shipped snippets verbatim — Claude.ai/Desktop
connector, Cursor `~/.cursor/mcp.json`, VS Code `.vscode/mcp.json`,
Codex `codex mcp add` + `codex mcp login`. They are verified against
docs/MCP.md; do not paraphrase commands.)

### Trust list — "How the keys stay yours"

- OAuth 2.1 with PKCE. Sign-in as an annotate dashboard user — GitHub or Google. Nothing to paste.
- `comments:read` is granted by default. Replying and resolving (`comments:write`) and deleting (`comments:moderate`) are opt-in on the consent screen.
- Revoke any client at `/dashboard/agents` — its next request is refused.
- Every write and every refusal is audited. Reads are never logged.
- Comment text is visitor-written: it arrives under an `untrusted` key, and the server tells the agent to treat it as data — never as instructions.

Closing line: `Prefer plain HTTP? The same threads, anchors, and live events
are on the REST API — reads are public unless you restrict them.`

CTAs: `Connect an agent` → `/dashboard/agents` · `Full MCP reference` → `/mcp-server`.

Evidence: docs/MCP.md (endpoint, OAuth 2.1/PKCE/DCR, scopes table, step-up
consent, revoke semantics, audit table, untrusted content, rate limits);
mcp_server_page.ex (tool table + client snippets); llms.txt agent section.

---

## 9. Social proof — placeholder strategy (all slots EMPTY)

No testimonials, logos, or metrics exist. Nothing may be invented. Strategy:

- **Ship without a social-proof section.** An empty section reads worse than
  none; the live-widget demo carries trust until proof exists.
- Slots reserved (do not render until filled):
  - `[METRIC SLOT — EMPTY: e.g. "N threads resolved on this page" — needs a real, citable counter]`
  - `[TESTIMONIAL SLOT — EMPTY: first site owner quote, with name + site, asked by email]`
  - `[CASE-STUDY SLOT — EMPTY: one agency write-up: before/after triage time]`
- The cheapest honest first proof: a real counter on the dogfood page
  ("N comments on this page, M resolved") — it is the product measuring
  itself. PROOF NEEDED: dashboard counter or public API read before use.

---

## 10. Add annotate to your site (embed snippet)

**Voice profile: agency_devs**

Heading: `Add your site, get your tag`
Steps:
1. `Create an account — sign in with GitHub.`
2. `Add your site's domain to your account.`
3. `Copy your script tag into your pages.`
Intro: `Your tag is two lines — the loader and the element — pasted before </body>. The loader you get tracks the newest build; pin a version if you'd rather nothing moves until you say so.`
Snippet: unchanged (script loader + `<noizu-page-comments site="…" api-base="…">`).
Button: `Copy code`
Caption: `Bound to the domain you registered — it won't fire anywhere else.`

Evidence: EMBED-AUTH § 0 (latest vs pinned loader, exact paths);
`landing_page.ex` snippet section renders `WidgetCdn.latest_src()`;
GitHub sign-in (`GithubAuth` component, llms.txt owner sign-in).

---

## 11. Privacy & security

**Voice profile: product_teams** (trust copy, plain)

Heading: `Built to stay out of the way`

- Tokens are bound to your origins — a key only works on the domains you register.
- No third-party cookies. The widget stores only what keeps a visitor signed in.
- Comments are publicly readable by default — restrict reading per site if you'd rather.
- Your comment data is yours: delete it from the dashboard, or ask us for an export.

Evidence: origin-bound HS256 tokens (README, EMBED-AUTH); per-site
`read_visibility` public/staff_only (`sites.ex`); widget storage rules
(EMBED-AUTH refresh-token table, `auth-storage="memory"` opt-out); dashboard
deletion + export path (privacy section, llms.txt).

---

## 12. Dogfood strip + final CTA

**Voice profile: agency_devs**

Dogfood strip (keep — it works):

> **This page runs annotate.** Select anything on it and leave a comment —
> you're looking at the product.
> `Try it on this page`

Final CTA section:

Heading: `Point at something.`
Body: `Install takes one snippet. The 14-day trial needs no card — and the comments you collect are yours to export or delete.`
Primary CTA: `Try it on this page`
Secondary CTA: `Add it to your site` → `#add-to-your-site`
Tertiary (quiet link): `See pricing` → `/pricing`

(The final CTA repeats the primary verb, per the hierarchy; urgency is only
the honest trial fact, no fake countdowns.)

Evidence: dogfood strip is shipped behavior; trial/no-card verified
(`pricing_page.ex`); export/delete verified (privacy claims above).

---

## 13. FAQ (8 real objections)

**Voice profile: agency_devs** (wry allowed; claims exact)

1. **Does the script slow my page down?**
   The widget loads asynchronously after your page renders and is cached at
   the edge. It doesn't block rendering and doesn't shift layout.
2. **Who can read the comments?**
   By default, anyone on the page can read and only signed-in visitors can
   post. Both are per-site switches.
3. **Do my visitors need annotate accounts?**
   No. They sign in through an Authentik popup — or, if you enable it, your
   own site vouches for its logged-in users and they never see our sign-in.
   Guest names and anonymous posting are per-site options.
4. **Can someone steal my key and use it on their site?**
   No. Keys are bound to the origins you register; requests from other
   domains are rejected.
5. **What happens to my comments if I cancel?**
   They stay readable — your sites go read-only until you pick a plan.
   Nothing is deleted on downgrade, and export is yours on request.
6. **Does it work with my stack?**
   If your page runs in a browser, yes. One script tag, no framework
   requirements, no build step.
7. **Can an AI agent act on the feedback — safely?**
   Over MCP, yes: the agent signs in as you, read is granted by default and
   writing is opt-in, every action is audited, and visitor text arrives
   labeled `untrusted` so the agent treats it as data, never instructions.
   Revoke any client at `/dashboard/agents`.
8. **Which trackers does it sync with — Jira, Notion, ClickUp?**
   None yet. Those integrations are planned; today the REST API covers
   programmatic export, and an agent over MCP can file the ticket on your
   side. Tick the boxes in the waitlist and you'll get one email per
   integration when it ships.

Changes vs the live FAQ: dropped "What data is stored per comment?" (a
privacy-policy answer, linked from § 11 — the nine-item FAQ was over quota);
merged visitor sign-in options into one objection (#3); added the cancel
objection (#5) and the agent-safety objection (#7) — the two questions this
product actually raises.

Evidence: async/edge-cached (EMBED-AUTH CDN table); public read + per-site
switches (`sites.ex`); popup broker + host-assert + guest/anonymous keys
(EMBED-AUTH, `sites.ex`); origin binding (CORS plug); cancel → read-only
(`pricing_page.ex` trial FAQ); browser-only requirement (COPY.md, unchanged);
MCP scopes/audit/untrusted (docs/MCP.md); integrations planned + waitlist
(`landing_page.ex` waitlist, seo.ex honesty rules).

---

## 14. Footer

**Voice profile: agency_devs (neutral)**

- Product: How it works · The loop · Features · For agents · Pricing · FAQ
- Resources: MCP server reference (`/mcp-server`) · `llms.txt` · `llms-full.txt`
- Legal: Privacy · Terms
- Publisher: `annotate is a The Robot Lives product.` → therobotlives.com · tobor.dev

Evidence: all targets exist (`seo.ex` @pages + llms.txt key pages; org
`same_as` list). No invented profiles or status page.

---

## 15. seo.ex replacements (@landing block + OG alt)

**Voice profile: agency_devs.** Drop-in strings for `AnnotateWeb.SEO`.
(Also flagged: the moduledoc's "no pricing" line and the `llms_*` pricing
paragraphs are stale against shipped `/pricing` — the .ex lane should
reconcile; see `marketing-overview.yaml` open_questions.)

```elixir
@landing %{
  title: "annotate — site feedback that points at the thing",
  description:
    "One script tag pins threaded comments to the exact element or text " <>
      "they're about. Triage in the dashboard, over the REST API, or with " <>
      "an AI agent over MCP. Free 14-day trial.",
  og_title: "annotate — site feedback that points at the thing",
  og_description:
    "One script tag pins threaded comments to the exact element or text " <>
      "they're about. Triage in the dashboard, over the REST API, or with " <>
      "an AI agent over MCP.",
  og_image: "/images/landing/og.png",
  og_image_width: 1200,
  og_image_height: 630,
  og_image_alt:
    "A visitor pins a comment to a page's Export button; the thread opens " <>
      "in the rail and an agent replies as the site team, resolving it."
}
```

Changes and why:

- **Title kept.** It already matches the v2 hero one-for-one ("points at the
  thing") — keeping it avoids splitting the message; it is 49 chars, distinct
  from generic "visual feedback tool" SERP copy.
- **Description:** adds "or text" (text-selection anchoring is shipped and
  was unsold) and the honest trial fact; still ≤ 155 chars rendered.
- **og_image_alt rewritten:** the old alt says the comment "becomes a
  ticket" — ticket push is planned, not shipped. The new alt describes only
  shipped loop steps (pin → rail → agent reply → resolve).
- Hero art note for the design lane: if the illustration itself still draws
  a ticket step, either re-cut it or caption it as the full loop including
  the planned step — open question already logged.

---

## 16. What changed vs COPY.md, and why

1. **Audience is now explicit and profiled.** COPY.md wrote for "the site
   owner" generically. V2 names `agency_devs` primary with a full voice card,
   and the MCP section switches to the `agent_first_teams` card — the two
   registers differ on purpose (dry-practical vs plain-technical).
2. **The loop, honestly chipped.** COPY.md predates the loop/MCP/integrations
   sections. V2 keeps the loop as the spine but strips "Ticket." from the
   section heading (a planned step must not headline a shipped story) and
   keeps Planned chips everywhere tickets appear. Same rule killed "becomes a
   ticket" in the OG alt.
3. **Pricing is in, where it ships.** COPY.md had none; `/pricing`,
   `Billing.Plans`, and Stripe checkout are live, so V2 adds the teaser
   section, the trial/no-card FAQ answer, and the trial line in the final
   CTA — all mapped to `pricing_page.ex`.
4. **Demo microcopy written for the click.** COPY.md stopped at CTA labels;
   V2 scripts the whole live-widget moment (pick hint, composer, sign-in
   gate, empty rail, post confirmation, agent handoff) because that click is
   the page's entire conversion mechanism.
5. **Kept from COPY.md:** the "Feedback that points at the thing" headline
   (promoted from option #1 to primary), the taboo list, "numbers over
   adjectives", the origin-bound-keys FAQ, the dogfood strip, and the embed
   intro. The 7-step gallery captions stay — they are accurate.

---

## 17. Self-check (voice card `agency_devs` + honesty rules)

| Rule | Pass/Fail | Note |
|---|---|---|
| Register: casual-technical, plain | PASS | No marketing register; sentences short and declarative |
| Tone: dry, understated | PASS | Wry only in FAQ; pricing matter-of-fact; MCP section flat-factual |
| Taboo phrases absent (seamless, effortless, game-changer, revolutionary, supercharge, "we're excited", 10x) | PASS | Zero hits across all sections |
| POV: you/your for owner; visitors third person | PASS | No "users"; "we" appears nowhere |
| Jargon: in-group terms only where they build trust | PASS | XPath/CSS confined to anchor copy; OAuth/PKCE/untrusted confined to § 8 |
| Colloquialisms: owned only | PASS | "the button near the top" (the pain, quoted), "drop in" — nothing dated |
| Locale en-US, consistent | PASS | No UK/US mixing found |
| Humor: dry at most, never in claims | PASS | |
| Emoji: none; ≤1 "!" per document | PASS | Zero exclamation points in body copy |
| CTA verb style: concrete verb + object | PASS | Try it on this page / Start free / Connect an agent — all verb-first |
| Trusted proof: demo + real numbers; nothing fabricated | PASS | Proof slots EMPTY (§ 9); no invented logos/metrics |
| Every claim maps to shipped code | PASS | Evidence line under every section |
| Planned vs shipped labeled everywhere | PASS | Chips in § 5; § 8 agent add-on not phrased as purchasable; § 13 Q8 "None yet" |
| Message consistency: tagline ↔ H1 ↔ SEO title | PASS | "points at the thing" is the single repeated phrase; no synonym drift ("pinned to the exact element" appears only in the one-liner/description, a deliberate plain-language restatement, not a replacement) |
| No pricing claims beyond shipped tiers | PASS | § 7 matches pricing_page.ex exactly; open question logged on stale llms.txt lines |

**Result: 15/15 PASS — no rewrites owed.**

Persistent disagreements to watch (none block): if the user later decides
tickets must NOT appear as a section at all until shipped, § 5 row 3 and the
integrations/waitlist sections collapse into a footnote — one-line change.
