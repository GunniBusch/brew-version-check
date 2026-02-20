# Brew Version Check

Static web app for GitHub Pages that checks source URL compatibility using a Ruby WebAssembly port of Homebrew logic. You manually enter a target version and the app shows the URL Homebrew would generate for a formula bump.

## What it checks

- Detects the current version from a source URL using Homebrew `Version.detect` logic.
- Accepts a manually entered target version.
- Generates the bumped URL using Homebrew `bump-formula-pr` `update_url` logic.
- Supports optional current-version override if URL detection is ambiguous.
- Optionally compares target version against current stable formula version from `formulae.brew.sh` API.
- Flags basic URL hints (HTTPS and common source archive extensions).

## Tech

- `ruby.wasm` runtime in browser.
- Homebrew-derived Ruby parser/comparator logic and URL rewrite logic in `/Users/leonadomaitis/pfusch/brew-version-check/app.rb`.
- Plain HTML/CSS/JS for UI and API fetch.

## Sync upstream Homebrew logic

To pull the latest upstream Homebrew source snapshots used for reference in this repo:

```bash
./scripts/sync_homebrew_logic.sh master
```

This updates:

- `/Users/leonadomaitis/pfusch/brew-version-check/vendor/homebrew/version.rb`
- `/Users/leonadomaitis/pfusch/brew-version-check/vendor/homebrew/version/parser.rb`
- `/Users/leonadomaitis/pfusch/brew-version-check/vendor/homebrew/dev-cmd/bump-formula-pr.rb`

## Run locally

Use any static server from repo root:

```bash
python3 -m http.server 8080
```

Open <http://localhost:8080>.

## Deploy to GitHub Pages

1. Push repository to GitHub.
2. In repository settings, open **Pages**.
3. Set **Source** to **GitHub Actions**.
4. The workflow at `/Users/leonadomaitis/pfusch/brew-version-check/.github/workflows/deploy-pages.yml` will deploy on every push to `main`.

## Notes

- Homebrew logic used here is a browser-friendly port, not a full Homebrew runtime.
- Formula metadata comparison requires network access to `https://formulae.brew.sh`.
- If `ruby.wasm` CDN URLs change, update the script tag in `/Users/leonadomaitis/pfusch/brew-version-check/index.html`.
- Homebrew upstream reference snapshot metadata is stored in `/Users/leonadomaitis/pfusch/brew-version-check/vendor/homebrew/SOURCE.md`.
- Third-party attribution is documented in `/Users/leonadomaitis/pfusch/brew-version-check/THIRD_PARTY_NOTICES.md`.

## License

This repository uses the same license as Homebrew (BSD 2-Clause). See `/Users/leonadomaitis/pfusch/brew-version-check/LICENSE`.
