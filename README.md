# Brew Version Check

Static web app for GitHub Pages that checks source URL and version compatibility using a Ruby WebAssembly port of Homebrew's version detection logic.

## What it checks

- Detects version from a source URL using Homebrew-style parser rules.
- Validates an optional declared version against detected URL version.
- Optionally compares detected version against current stable formula version from `formulae.brew.sh` API.
- Flags basic URL hints (HTTPS and common source archive extensions).

## Tech

- `ruby.wasm` runtime in browser.
- Homebrew-derived Ruby parser/comparator logic in `/Users/leonadomaitis/pfusch/brew-version-check/app.rb`.
- Plain HTML/CSS/JS for UI and API fetch.

## Run locally

Use any static server from repo root:

```bash
python3 -m http.server 8080
```

Open <http://localhost:8080>.

## Deploy to GitHub Pages

1. Push repository to GitHub.
2. In repository settings, enable GitHub Pages and choose deploy from branch.
3. Select your branch (for example `main`) and root folder (`/`).
4. Save. GitHub Pages will host `index.html`.

## Notes

- Homebrew logic used here is a browser-friendly port, not a full Homebrew runtime.
- Formula metadata comparison requires network access to `https://formulae.brew.sh`.
- If `ruby.wasm` CDN URLs change, update the script tag in `/Users/leonadomaitis/pfusch/brew-version-check/index.html`.
- Third-party attribution is documented in `/Users/leonadomaitis/pfusch/brew-version-check/THIRD_PARTY_NOTICES.md`.

## License

This repository uses the same license as Homebrew (BSD 2-Clause). See `/Users/leonadomaitis/pfusch/brew-version-check/LICENSE`.
