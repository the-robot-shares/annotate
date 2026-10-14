# Design system assets

## `theme-style-guide/`

YAML theme facets for the [@noizu/styleguide](../../styleguide) engine (same layout as `start-app/frontend/src/config/theme-style-guide/`).

Pre-generated CSS is committed under:

```
backend/priv/static/themes/design-system.generated.css
backend/priv/static/themes/style-guide.css
```

## Regenerating CSS

From a host with Node 20+ and access to `@noizu/styleguide` (Verdaccio / npm.noizu.com):

```bash
# Example using the styleguide package CLI / generate entry
# Point THEME_DIR at this directory and OUT at backend priv/static/themes
```

Or copy a fresh build from the styleguide app / start-app frontend after `npm run regen`.

## Hologram components

UI primitives that consume these CSS classes live in:

`backend/lib/starter_web/hologram/components/`
