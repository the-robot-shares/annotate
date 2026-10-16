# Annotate — Landing Page IA + Wireframe

Page: `annotate.therobotlives.com` (Hologram/Elixir). The page runs the live
widget itself — the primary CTA puts the visitor into the real comment flow on
this very page. Section order and wireframe below; copy lives in `COPY.md`,
visual direction in `DIRECTIONS.md`.

## Section list

1. **Nav** — wordmark, anchors (How it works, Features, Privacy, FAQ), CTA "Try it on this page".
2. **Hero** — headline, subhead, primary CTA "Try it on this page" (activates the widget inline), secondary "Add to your site" (jumps to embed snippet). Hero art: generated illustration per chosen direction.
3. **How it works** — 3 steps: 1) Drop in the script 2) Pick any element or text 3) Discuss in the rail.
4. **Feature bento** — 7 tiles: anchored rail · ring highlight · threads · attachments · screenshot + annotate · live updates · per-site rules & SSO.
5. **Embed snippet** — one script-tag block, copy button, service-key note.
6. **Privacy & security** — origin-bound tokens, no third-party cookies, public read default, data ownership.
7. **Dogfood strip** — "This page runs annotate. Right now." with widget affordances (see states below).
8. **FAQ** — 6 items.
9. **Footer** — The Robot Lives family links, docs, status, legal.

## ASCII wireframe (desktop)

```
┌──────────────────────────────────────────────────────────────────────┐
│ annotate            How it works  Features  Privacy  FAQ   [Try it]  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   HEADLINE (h1, 2 lines max)                    ┌──────────────────┐ │
│   Subhead: one sentence, plain.                 │   HERO ART 16:9  │ │
│                                                 │ webpage + ring + │ │
│   [ Try it on this page ]  [ Add to your site ] │ comment rail     │ │
│   caption: no signup needed to look around      └──────────────────┘ │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  HOW IT WORKS                                                        │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐                    │
│  │ 1 Drop in  │ → │ 2 Pick any │ → │ 3 Discuss  │                    │
│  │ the script │   │ element    │   │ in the rail│                    │
│  └────────────┘   └────────────┘   └────────────┘                    │
├──────────────────────────────────────────────────────────────────────┤
│  FEATURES (bento: 2 wide + row of 3 + 2 wide)                        │
│  ┌──────────────────────────┐  ┌──────────────────────────┐          │
│  │ Anchored rail            │  │ Ring highlight           │          │
│  │ floats beside the element│  │ click a comment, the     │          │
│  │ on any layout            │  │ element rings            │          │
│  └──────────────────────────┘  └──────────────────────────┘          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                              │
│  │ Threads  │ │ Attach-  │ │ Live     │                              │
│  │ & replies│ │ ments    │ │ updates  │                              │
│  └──────────┘ └──────────┘ └──────────┘                              │
│  ┌──────────────────────────┐  ┌──────────────────────────┐          │
│  │ Screenshot + annotate    │  │ Per-site rules + SSO     │          │
│  │ crop, boxes, arrows, pen,│  │ Authentik popup, or your │          │
│  │ text, blur               │  │ site vouches for users   │          │
│  └──────────────────────────┘  └──────────────────────────┘          │
├──────────────────────────────────────────────────────────────────────┤
│  ADD TO YOUR SITE                                                    │
│  ┌───────────────────────────────────────────────┐ ┌──────────────┐   │
│  │ <script src="https://annotate…/widget.js"     │ │  Copy code   │   │
│  │  data-key="YOUR_SERVICE_KEY"></script>        │ │              │   │
│  └───────────────────────────────────────────────┘ └──────────────┘   │
│  Create a site key in the dashboard · rules are per-site             │
├──────────────────────────────────────────────────────────────────────┤
│  PRIVACY & SECURITY   origin-bound tokens · no third-party cookies · │
│  public read by default (configurable) · you own your comment data   │
├──────────────────────────────────────────────────────────────────────┤
│  THIS PAGE RUNS ANNOTATE  →  comment banner: try the real widget     │
├──────────────────────────────────────────────────────────────────────┤
│  FAQ (6, accordion)                                                  │
├──────────────────────────────────────────────────────────────────────┤
│  Footer: The Robot Lives · Docs · Status · Privacy · Terms           │
└──────────────────────────────────────────────────────────────────────┘
```

Mobile: hero art drops below CTAs; bento collapses to single column (order:
ring, threads, screenshot+annotate, rail, attachments, live, rules); snippet
block becomes horizontally scrollable; rail note explains it docks right on
desktop, bottom sheet on mobile.

## Dogfood widget states (this page)

| State | Behavior |
|---|---|
| Signed out, public read on | Rail visible in read-only; existing page comments browsable; composer shows "Sign in to comment" → Authentik popup; after sign-in the draft survives. |
| Signed in | Composer focused-ready at rail top; posting appends locally and live-syncs to other open sessions; attachments + screenshot buttons enabled. |
| No comments on page yet | Rail shows empty state: "No comments on this page yet. Select any text or element to start one." + a one-time coach-mark pointing at the page body. |
| Widget loading / JS failed | Rail absent; a quiet footer chip "annotate: comments unavailable" (never blocks page render). |
| Host vouches (no popup) | If the host site issues a vouch token, composer opens signed-in with host identity, no Authentik step. |

Rule: the widget must never intercept normal page interactions; a visible
"exit" affordance exists while selection mode is armed.
