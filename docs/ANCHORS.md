# Anchor fidelity — page context, element anchors, deep links

Every thread records **where it was written** (the exact page) and **what it points at** (a multi-strategy
element anchor), so the exact item can be found again. Migration: `backend/db/changelog/033-annotate-anchor-fidelity.yaml`
(additive only; changeset ids `annotate-0041..0043`).

## Stored fields (`threads`)

| Field | Type | Notes |
|---|---|---|
| `url` | text | Full href at write time (minus the `#annotate=` token). Legacy rows: backfilled from `pages.last_url`. |
| `origin` | varchar | `scheme://host[:port]`, lowercased host. |
| `page_path` | varchar | Normalized: leading `/`, no trailing `/` (root = `/`). Indexed. |
| `query_string` | text | Raw, no leading `?`. NULL on legacy rows. |
| `query_params` | jsonb | Parsed map; repeated keys -> sorted array. **NULL = legacy, matches any query.** |
| `hash` | text | Fragment at write time. |
| `page_title` | varchar | `document.title`. |
| `anchor_version` | smallint | 1 = legacy anchor, 2 = multi-strategy (taken from `anchor.v`). |
| `anchor` | jsonb | See below. |

The server derives all page fields from `url` when present (authoritative); `page_path` / `query_string` /
`query_params` / `hash` in the request body are fallbacks for url-less writers.

## Anchor v2 (`threads.anchor`)

```json
{ "v": 2,
  "css": "...unique selector...", "xpath": "/html[1]/body[1]/...",
  "textQuote": {"prefix": "", "exact": "", "suffix": ""},
  "fingerprint": {"tag": "p", "textHash": "…", "relPos": 0},
  "target": "element|range",
  "ids": {"id": "hero", "data": {"data-testid": "buy"}},
  "position": {"bbox": {"x":0,"y":0,"w":0,"h":0}, "viewport": {"w":0,"h":0}, "scroll": {"x":0,"y":0}, "doc": {"w":0,"h":0}},
  "textPosition": {"start": 0, "end": 0} }
```

`ids` / `position` / `textPosition` are optional; v1 anchors (no `v`) still resolve.

### Resolution order (client)

`id` -> `data-*` -> unique `css` -> `xpath` -> `text` quote -> `position` (bbox IoU >= 0.5, never scrolls).
Each hit is validated against the fingerprint; earlier strategy wins ties. A stable id/data hook whose tag
matches is treated as identity. Result carries `strategy` and `approx` (true when only `position`,
`text-position`, or a low-confidence match found it). Nothing matches = orphan. Range anchors resolve by text
quote, then `textPosition` as an approx fallback.

## Query-param matching

`GET /api/v1/sites/:site/threads?page_key=…&query=<raw current query>` (or `&url=<full current url>`) returns
only threads whose stored `query_params` match, order-insensitively. Without `query`/`url` the whole page is
returned (legacy behaviour). `&ignore_params=a,b` adds request-level ignores.

Per-site significance (default: **all params significant**) in `sites.settings`:

```json
{"anchor": {"ignore_query_params": ["utm_*", "fbclid"], "significant_query_params": []}}
```

Trailing `*` = prefix glob; a non-empty `significant_query_params` is an allow-list. Applied at read time, so
changing it re-groups existing threads. Widget attrs `ignore-query-params` / `significant-query-params` do the
same client-side (realtime filtering, URL-change reloads).

## Deep link

Thread payloads carry `deep_link` = `<url without fragment>#annotate=<thread_id>` (null when `url` is unknown).
Opening it (or changing the hash) makes `<noizu-page-comments>` open the island, load the page's threads,
focus the thread, scroll to the element and ring it, then emit `page-comments-deeplink`
(`{id, found, resolved, approx, strategy}`). The dashboard comments inbox should link to `thread.deep_link`.

## API additions

`POST /sites/:site/threads` accepts `url`, `title`, optional `page_path`, `query_string`, `query_params`, `hash`.
Thread JSON adds: `anchor_version`, `url`, `origin`, `page_path`, `query_string`, `query_params`, `hash`,
`page_title`, `deep_link`.
