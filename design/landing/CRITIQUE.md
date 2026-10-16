# Annotate — Landing Direction Critique

Renders of all four directions from `design/landing/prompts/*` (model pinned per file:
`gemini-2.5-flash-image`, quality high). Images live in `renders/<direction>/`.
**All images are AI-generated and must carry an AI-generated disclosure wherever published.**

## Render log (eval gate = per-prompt `eval` block)

| Image | Attempts | Eval result | reject_if hits | Vision re-check |
|---|---|---|---|---|
| `renders/margin/hero.png` | 3 (1 + 2 fallback, budget spent) | **FAIL** — best 0.750 / 0.712 / 0.700, required `composition` never passed; saved best-available | none | no text/logos; usable but weakest render |
| `renders/margin/feature-screenshot-annotate.png` | 1 | PASS 0.887 | none | pass |
| `renders/night-desk/hero.png` | 1 | PASS 0.938 | none | pass |
| `renders/night-desk/feature-screenshot-annotate.png` | 1 | PASS 0.938 | none | pass |
| `renders/red-pen/hero.png` | 1 | PASS 0.938 | none | pass |
| `renders/red-pen/feature-screenshot-annotate.png` | 1 | PASS 0.938 | none | pass |
| `renders/proof-sheet/hero.png` | 1 | PASS 0.938 | none | pass |
| `renders/proof-sheet/feature-screenshot-annotate.png` | 1 | PASS 0.938 | none | pass |

Contact sheet: `renders/contact-sheet.png` (2 columns hero | feature × 4 rows, labeled).

## 1. Night Desk (Nocturne) — 8.5/10

Both renders nail the product story: the ember ring is unambiguously the brightest
element in the hero and the raised comment rail reads docked, with a luminous connector
to the pinned comment — the widget's signature interaction is the image. Single-glow
discipline held in both frames (one warm hue, everything else brightness steps), so
nothing skews gamer-y; the feature editor is credible with a glowing marquee, box,
arrow, pen squiggle and dot-matrix blur. Brand fit is strong for a creative-tool
audience and it is the most differentiated hero of the four at a glance. Pairs cleanly
with the Geist/Inter + JetBrains Mono and ember palette in DIRECTIONS.md — these renders
basically *are* the palette. Risks: the real product UI is light-mode, so every real
screenshot needs a dark re-shoot or dark mat (dogfood honesty per DIRECTIONS); long copy
sits worse on dark; the feature's "crop marquee" renders as a whole-page glowing frame
rather than a sub-region — fix in a v2 prompt or accept as stylistic license.

## 2. Red Pen — 8/10

The most memorable hero: one dominant textured circle with overshoot, highlighter wash,
margin arrow and ticks over a strict grid, while the three-card rail stays deliberately
tidy — the messy-marks-become-organized-threads idea lands without a caption. Feature
render delivers all four annotation types distinctly (double-traced box, arrow,
squiggles, pixel blur) with a crisp crop frame and glyph-only toolbar, plus the little
blue asterisk. Pairs naturally with Space Grotesk display + Caveat margin notes; the
hand/tidy contrast maps directly onto the motion plan (marks draw on, cards settle).
Risks: palette drifted warm — the red reads terracotta rather than `#E5342B` and the
blur square is red-tinted where it should read neutral; hero rail cards float just off
the page edge instead of docking flush; highest execution variance of the four if
re-shot, and enterprise buyers may read it as gimmicky (DIRECTIONS risk confirmed but
not disqualifying).

## 3. Proof Sheet — 7.5/10

Precise and calm: corner crop marks, a registration target, a disciplined red ellipse
and one blue revision tag, with the rail reading as attached correction flags — the
blue=system / red=annotation role split survives in both frames, which was this
direction's main hazard. The feature render is arguably the best editor mock of the
eight (crisp marquee, clean triangular arrow, steady underline, blue-highlighted crop
glyph). Pairs well with the all-IBM-Plex system; mono labels will flatter the embed
snippet. Why it ranks below the top two: the hero is academically empty — the proof
sits small in a large field and the metaphor needs a beat of explanation, which a hero
doesn't get; the comment rail reads as three detached cards more than one rail; and the
feature's red marquee escapes the page onto the paper margin (a "marks stay inside the
artboard" miss). Niche-metaphor risk from DIRECTIONS stands: if the audience doesn't
parse proof rounds, it's noise.

## 4. Margin — 7/10

The feature render is the cleanest editor of the eight — dashed marquee, six-glyph
toolbar with the pen ringed red, box/arrow/squiggle/dot-blur all distinct, perfect
paper-and-ink restraint. The hero, however, underdelivered: three eval attempts (best
0.750, required composition never passed) and the result shows it — the ring is thin
and faint, the rail floats a visible gap off the page edge, the whole subject sits
small and low in the frame with dead space above. Story elements are present but the
hero doesn't demo the product so much as illustrate a document. Pairs perfectly with
Newsreader/Inter + the `#D92D20` accent (it is the house palette), and it remains the
safest, fastest-to-ship direction. Risks: exactly the DIRECTIONS warning — generic if
whitespace discipline slips, and abstraction fatigue is real without real product
shots. **Recommendation: if Margin is chosen, re-render the hero (tighter composition,
heavier ring, rail flush-docked) or substitute a real dogfooded screenshot.**

## Ranking

1. **Night Desk (8.5)** — best product-story legibility (ring-as-hero literally demos
   the widget), most differentiated, most internally cohesive pair. Main cost: dark
   re-shoot of all real screenshots.
2. **Red Pen (8)** — most memorable and the clearest "this product IS markup" read;
   accept palette drift or do one targeted re-roll.
3. **Proof Sheet (7.5)** — most precise execution, best editor mock, but the hero
   lacks presence and the metaphor is audience-dependent.
4. **Margin (7)** — safest brand fit and best-in-class feature render, but the hero
   render failed its own gate and needs a re-roll before this direction is presentable.

Cross-cutting note: every render kept text fully abstract — zero legible words, no
brand logos, no watermarks in any of the eight, so the shared "no fake UI copy" rule
held across the board.
