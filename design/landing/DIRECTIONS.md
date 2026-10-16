# Annotate — Marketing Landing Page: Visual Directions

Status: DRAFT — approval gate. No images generated yet. After the user picks a
direction, run its prompts:

    generate-media-prompt design/landing/prompts/<slug>/hero.media.prompt
    generate-media-prompt design/landing/prompts/<slug>/feature-screenshot-annotate.media.prompt

All images produced from these prompts are AI-generated and must carry an
AI-generated disclosure wherever published (caption, alt text, or credits line).

Shared context: the landing page itself runs the live widget (dogfood). Every
direction must keep generated hero/feature art visually consistent with the
real UI: right-docked floating comment rail, ring highlight on the commented
element, threaded cards, abstract (bar-style) text. Generated art shows
abstracted text bars, never legible UI copy and never real brand logos.

---

## 1. Margin — Minimal Tech + Editorial (RECOMMENDED DEFAULT)

Mood: A well-set document, calm and confident; feedback floats in the margin
like a copy-editor's pencil marks. Whitespace does the work; one red accent
carries every annotation.

- Palette: paper `#FAFAF8` · surface `#F1F1EE` · ink `#17171C` · secondary text `#5B5B66` · border `#E4E4DF` · markup red (accent) `#D92D20` · link blue `#2563EB`
- Type: Newsreader (serif display headlines) + Inter (UI/body) + JetBrains Mono (snippet). Serif = the review/critique heritage; sans keeps product UI credible.
- Motion: 150–200ms ease-out; ring draws on via SVG stroke-dashoffset (~400ms); rail cards fade+12px slide, staggered 40ms; reduced-motion → opacity only.
- Rationale: audience (product, design, QA) reads restraint as competence; the red-pen accent literally demos the product; aligns with the app theme seeds (Inter + JetBrains Mono, red accent family `#e53e3e`) so dogfooding looks native.
- Risks: generic if whitespace discipline slips; red overuse reads as errors — cap it to rings, pins, CTAs; needs real product shots to avoid abstraction fatigue.
- Prompts: `prompts/margin/hero.media.prompt`, `prompts/margin/feature-screenshot-annotate.media.prompt`

## 2. Night Desk — Nocturne

Mood: An after-hours review session: dark canvas, one warm glow. Comments glow
softly beside dimmed page content like pin-lights on a dark board.

- Palette: void `#0B0B10` · canvas `#111118` · surface `#1A1A23` · raised `#23232E` · mist border `#2A2A3A` · text dim `#6B6B80` / secondary `#9A9AB0` / primary `#D6D6E4` · ember glow `#F97316` (bright `#FB923C`, ambient 8%)
- Type: Geist (display at 300–400 weight) + Inter (body) + JetBrains Mono (snippet, glow-tinted tokens).
- Motion: ambient glow pulse 4s on the active comment pin; hover intensifies halo (never dims); 200ms ease-out; skeleton shimmer mist→fog; reduced-motion strips halos, keeps solid 2px outline.
- Rationale: the ring/glow interaction is the product's signature — luminosity hierarchy demos it honestly; strong differentiation in a white-box SaaS field; suits the creative-tool audience (designers, agencies).
- Risks: light-mode product screenshots clash — every screenshot must be re-shot dark or framed on a dark mat; long copy is harder on dark; overdone glow skews gamer-y.
- Prompts: `prompts/night-desk/hero.media.prompt`, `prompts/night-desk/feature-screenshot-annotate.media.prompt`

## 3. Red Pen — Marked-Up Paper (expressive option)

Mood: A page fresh from a demanding editor: oversized hand-drawn circles,
underlines, and arrows in red ink on bright paper. The layout stays clean so
the marks do the talking.

- Palette: bright paper `#FFFDF6` · ink `#1A1A1F` · red pen `#E5342B` · highlighter wash `#FFE066` (≤20% opacity fills) · blue pen `#2F5FE0` · pencil gray `#8A8A93`
- Type: Space Grotesk (display) + Inter (body) + Caveat (margin notes only — never body, never buttons).
- Motion: marks draw on (stroke animation 300–500ms); cards settle with a 1–2deg rotate; CTA stamps in (scale 1.06→1, 150ms); all ≤300ms, reduced-motion → fades.
- Rationale: the product IS markup — leaning into the metaphor makes the hero instantly legible without a caption; most memorable of the four; conversion stays safe because body layout remains strict Minimal-Tech underneath.
- Risks: highest execution risk; hand-drawn assets must never collide with real UI screenshots (keep marks in whitespace zones); Caveat fails contrast — decorative only; enterprise QA buyers may read it as gimmicky.
- Prompts: `prompts/red-pen/hero.media.prompt`, `prompts/red-pen/feature-screenshot-annotate.media.prompt`

## 4. Proof Sheet — Print Production (alternate)

Mood: A prepress proofing table: crop marks, registration targets, approval
stamps. Feedback as a print-production ritual — precise, technical, quietly
confident.

- Palette: proof paper `#F4F4F1` · ink `#14161A` · registration blue `#2F6FED` · proof red `#E5484D` · crop-mark gray `#B9BBB6`
- Type: IBM Plex Sans (all UI/body/headlines) + IBM Plex Mono (labels, snippet, crop-mark captions).
- Motion: crop-mark corners align on scroll-into-view (200ms); section labels tick like registration targets; stamp CTAs land 150ms scale; reduced-motion → static.
- Rationale: agencies and client-feedback buyers already speak "proof round"; mono-heavy pairing flatters the developer embedding the snippet; bluish/red duotone is printable and calm.
- Risks: metaphor is niche — if the audience doesn't parse crop marks it's noise; blue+red needs strict role separation (blue = system, red = annotation); can skew retro without modern spacing.
- Prompts: `prompts/proof-sheet/hero.media.prompt`, `prompts/proof-sheet/feature-screenshot-annotate.media.prompt`

---

## Decision notes

- If the user wants the safest, fastest-to-ship page: **Margin**.
- If they want the widget to be the visual star: **Night Desk**.
- If they want personality and accept re-shooting all art: **Red Pen**.
- Any direction must be applied to the real screenshots too (dogfood honesty);
  generated hero/feature art is illustrative, the bento tiles use real UI.
