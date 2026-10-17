# RENDERS — D1/D2/D3 full-page mockups (annotate landing revamp)

Generated 2026-10-18, Gate A passed (D1/D2/D3 approved). Tool: `generate-media-prompt`
CLI (nano banana, `gemini-2.5-flash-image`, quality high, 832x1248 PNG) — primary rung
of the ladder, no downgrade.

**Rounds:** 3 per direction — initial, refinement pass (gate-fail fixes), and a
correction re-render after the user's 2026-10-18 copy correction (hero secondary CTA
"Add to your site" → "Start free", plus hero caption and embed heading; the correction
message authorized re-rendering completed renders). 9 renders total — the original
"≤6" budget was exceeded by the correction round. Round-1/2 renders are preserved as
`full-page.r1.png` / `full-page.r2.png` beside each prompt.

**Copy correction applied to all three string manifests** (renders show: annotate,
headline, subhead, Try it on this page, Start free, hero caption, Add your site get
your tag, Export, [patch ready / Resolved on D1/D2], Soon, FAQ). The three embed steps
render as bars for text budget; full strings live in COPY-v2 §10.

**Systemic issue (all rounds, all directions):** nano banana cannot reliably spell
"annotate" at wordmark size — every render garbles it (antodade / annocate / annozate /
annoate / anodeste / anodbate). Headline, CTAs, "Start free", the embed heading, and
section structure render reliably. The real build sets wordmark text in HTML, so this
affects mockup polish, not direction choice. No further re-rolls were available within
the one-refinement + one-correction budget.

---

## D1 — Ember Nocturne v2

- Prompt: `design/landing/prompts/d1-ember-nocturne-v2/full-page.media.prompt`
- Render: `design/landing/renders/d1-ember-nocturne-v2/full-page.png` (r1/r2 in prompts dir)
- **Score: 6.5/10** — accent discipline and hero staging hold (ember ring + pin + CTAs
  are the only saturated elements, ring reads as centerpiece); "Start free", "patch
  ready", "Soon", "Add your site, get your tag", icon-only copy button all correct;
  code panel finally clean bars.
- Defects: (1) headline renders a spurious trailing "about."; (2) hero caption garbled
  ("No sigrup… istall… tm account"); (3) wordmark garbled ("annozate") and final ember
  strip rendered oversized/empty; walkthrough row shows 6 thumbs, bento 4 tiles.
- Eval gates: text_legibility FAIL (headline + caption + wordmark), full_page_structure
  PASS- (order kept, counts drift), accent_budget PASS.
- **Recommendation:** keep as the dark-systems fallback; the v2 composition discipline
  is real but this round's text regressions need a re-roll before any public use.

## D2 — Blueprint Ember

- Prompt: `design/landing/prompts/d2-blueprint-ember/full-page.media.prompt`
- Render: `design/landing/renders/d2-blueprint-ember/full-page.png` (r1/r2 in prompts dir)
- **Score: 5.5/10** — the substrate works (faint grid, crop-corner ticks, registration
  marks, instrument-panel rail flush-docked); "Export" legible in-ring this round;
  "Start free" + embed heading correct; code panel clean.
- Defects: (1) hero caption heavily garbled with duplicated fragments; (2) subhead
  garbled ("anodeste pina threadad… elerizent or tetl"); (3) off-manifest garbled
  "Roadmap" label and FAQ again landed on the final strip; 7-thumb walkthrough degraded
  to a tiny strip of squares; wordmark garbled.
- Eval gates: text_legibility FAIL, full_page_structure FAIL- (FAQ position, missing
  walkthrough row), grid_discipline PASS, accent_budget PASS.
- **Recommendation:** weakest text fidelity of the three; the drafting-substrate idea
  survives but needs a mono-wordmark workaround (or post-edit label swap) before it can
  compete.

## D3 — Daylight Margin v2

- Prompt: `design/landing/prompts/d3-daylight-margin-v2/full-page.media.prompt`
- Render: `design/landing/renders/d3-daylight-margin-v2/full-page.png` (r1/r2 in prompts dir)
- **Score: 7.5/10** — best text fidelity (hero caption near-perfect, one garbled word;
  headline, both CTAs, embed heading, FAQ, Soon all crisp), structure closest to the
  approved IA, rail flush-docked with no gap, heavy confident ring, editorial margins.
- Defects: (1) wordmark garbled ("annoate") — the systemic issue; (2) off-manifest
  "Bento greid" label; (3) the red ring wrapped the rail card instead of a page element
  inside the browser (loop story reads on the rail, not the page); bento shows 4 tiles.
- Eval gates: text_legibility PASS- (wordmark only), full_page_structure PASS-,
  rail_flush_docked PASS, ring_weight PASS.
- **Recommendation:** pick this render if the choice is made on mockup evidence — it is
  the only one where a stranger could read the page; fix the ring-subject in the build.

---

## Recommendation order

1. **D3 Daylight Margin v2 (7.5)** — cleanest text, best structure; decide the
   widget-theme question (dark rail on light page = current honest default) in the build.
2. **D1 Ember Nocturne v2 (6.5)** — strongest dark-system story and accent budget;
   needs one more text re-roll (headline/caption) before it could ship as art.
3. **D2 Blueprint Ember (5.5)** — best "engineering instrument" concept, worst render
   fidelity; keep the direction, regenerate later with a shorter string manifest.

Caveat for the gate: direction choice should weigh the DIRECTIONS.md strategy case
(D1 = polish of the shipped Night Desk) against render fidelity observed here; the
wordmark garble is a generator limitation, not a direction defect.
