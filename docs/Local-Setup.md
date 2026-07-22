# Local Wrangler / Cloudflare Worker Setup

Notes on how to get `rssparam` running locally with `wrangler dev` and how the environment was set up for this repo.

## Prerequisites

- Homebrew
- `node` and `npm` (installed via `brew install node`)
- `gh` GitHub CLI (installed via `brew install gh`)
- `jq` (was already present on this Mac at `/usr/bin/jq`)

## Project structure

The worker code lives in `rssparam/rssparam/`, not the repo root:

```
celadyn/rssparam/
├── rssparam/
│   ├── package.json
│   ├── wrangler.toml
│   └── src/
│       └── index.ts
└── .github/workflows/deploy.yml
```

## Install dependencies

```bash
cd /Users/dsr/Library/CloudStorage/OneDrive-Personal/Repos/celadyn/rssparam/rssparam
npm install
```

### Dependency conflict fix

`npm install` initially failed with an `ERESOLVE` conflict:

- `wrangler@4.112.0` expected `@cloudflare/workers-types@^5.x`
- `package.json` pinned it to `^4.20240925.0`

Fixed by bumping the dev dependency in `rssparam/package.json`:

```json
"@cloudflare/workers-types": "^5.20260714.1"
```

### Install-script approval

`npm` blocked install scripts for `esbuild`, `workerd`, and `sharp`. Before `wrangler dev` can start, allow those scripts:

```bash
npm approve-scripts --allow-scripts-pending
```

## Run the local dev server

```bash
npm run dev
```

This starts `wrangler dev` and serves on:

```
http://localhost:8787
```

It hot-reloads on file changes.

## Test URLs

Single feed:

```
http://localhost:8787/?rss=https://www.theverge.com/rss/index.xml&count=3
```

Multiple feeds:

```
http://localhost:8787/?rss=https://www.theverge.com/rss/index.xml&rss=https://news.ycombinator.com/rss&count=3
```

## GitHub Actions auto-deploy

The repo already contains `.github/workflows/deploy.yml`. It deploys to Cloudflare on every push to `main` and on `workflow_dispatch`.

Required GitHub repository secrets:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN` with `Cloudflare Workers:Edit` and `Account:Read` permissions

To trigger manually:

```bash
gh workflow run deploy.yml --repo celadyn/rssparam
```

## Useful commands

```bash
# Check recent GitHub Actions runs
gh run list --repo celadyn/rssparam --limit 10

# View the deploy workflow
gh workflow view deploy.yml --repo celadyn/rssparam
```
