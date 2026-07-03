# Vendored static deps

These files are vendored on purpose — no npm, no CDN at runtime.
Pin a known-good version + SHA. Verify before committing.

## htmx.min.js

Path: `backend/static/vendor/htmx.min.js`

Download (verify the URL on https://htmx.org before running):

```bash
curl -fsSL https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js -o backend/static/vendor/htmx.min.js
```

Verify SHA-256 against https://htmx.org/docs/#installing or the npm registry's reported integrity for that exact version:

```bash
shasum -a 256 backend/static/vendor/htmx.min.js
```

Commit the file. Future upgrades = bump version + re-verify SHA. No build step ever touches `node_modules`.

## leaflet.js / leaflet.css

Add when the map view is ported (later slice). Same pattern: download + SHA verify + commit.
