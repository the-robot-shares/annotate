# Annotate — Landing Page Copy

Plain, specific, no hype words. Claims are limited to shipped behavior:
script-tag install, element/text selection, right-hand rail, ring-on-click,
threads, attachments, screenshot crop + annotate (boxes, arrows, pen, text,
blur), live updates, per-site rules, Authentik SSO or host-vouched identity,
public read by default.

## Headline options

1. **Feedback that points at the thing.**
   Subhead: annotate adds a comment rail to any webpage. Visitors select an
   element or some text, and the thread attaches to exactly that spot.
2. **Put comments on the page, not below it.**
   Subhead: One script tag turns any site into something you can mark up —
   element-level threads, screenshots, and replies in a floating rail.
3. **Drop in a script. Let the page take the notes.**
   Subhead: annotate pins threaded comments to the elements they're about, so
   nobody writes "the button near the top" again.

Recommendation: #1 — it names the mechanic without naming the stack.

## Section copy

**Hero CTAs:** primary `Try it on this page` · secondary `Add to your site`
Hero caption: `No signup needed to look around. Sign-in is required to post.`

**How it works**
1. Drop in the script — one tag in your HTML with your site's service key.
2. Pick any element — visitors click a component or highlight text.
3. Discuss in the rail — threads open beside the element; clicking a comment
   rings the spot it refers to.

**Feature bento**
- Anchored rail — The comment rail floats beside the element on any layout; it follows scroll and never covers what you're discussing.
- Ring highlight — Open a comment and the element it belongs to rings on the page, so review starts at the right spot.
- Threads — Replies nest under each comment; resolve a thread when it's settled.
- Attachments — Add files and images to any comment.
- Screenshot + annotate — Crop the page, then draw boxes, arrows, and freehand, add text, or blur anything sensitive.
- Live updates — New comments and replies appear without a refresh.
- Per-site rules and SSO — Decide who can post per site: sign-in through your Authentik, or your own site vouches for its users. Reading is public by default.

**Embed snippet** section intro: `Paste this before </body>. Replace the key with the service key for your site.`
Button: `Copy code`. Caption: `Create keys and set rules in the dashboard.`

**Privacy & security**
- Tokens are bound to your origin — a key only works on the domains you register.
- No third-party cookies; the widget stores only what it needs to keep you signed in.
- Comments are publicly readable by default; you can restrict reading per site.
- Your comment data is yours — export or delete it at any time.

**Dogfood strip:** `This page runs annotate. Select anything on it and leave a comment — you're looking at the product.`

## CTA labels

| Placement | Label |
|---|---|
| Nav / hero primary | Try it on this page |
| Hero / snippet secondary | Add to your site |
| Snippet | Copy code |
| Sign-in prompt in rail | Sign in to comment |
| Empty rail | Start the first comment |

## FAQ

1. **Does the script slow my page down?** The widget loads asynchronously after your page renders and is cached at the edge. It doesn't block rendering and doesn't shift layout.
2. **Who can see the comments?** By default anyone on the page can read, and only signed-in visitors can post. Both can be changed per site.
3. **How do visitors sign in?** Through an Authentik popup, or — if you enable it — your own site vouches for its logged-in users, so your users never see our sign-in.
4. **Can someone use my key on their site?** No. Keys are bound to the origins you register; requests from other domains are rejected.
5. **What can people attach?** Files and images on any comment, plus screenshots taken on the page — cropped, with boxes, arrows, freehand pen, text, and blur drawn on top.
6. **Does it work with my stack?** If your page runs in a browser, yes — one script tag, no framework requirements, no build step.

## Voice notes

- Short declarative sentences; second person for the site owner, third person for visitors.
- Never: revolutionary, game-changing, seamless, effortless, supercharge.
- Numbers over adjectives where a claim exists (one script tag, six tools, two identity options).
