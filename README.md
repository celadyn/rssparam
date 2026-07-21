# rssparam

Cloudflare Worker that renders RSS feed items from one or more `?rss=` URL parameters.

## Usage

Single feed:

```
https://rssparam.<your-subdomain>.workers.dev/?rss=https://www.theverge.com/rss/index.xml&count=3
```

Multiple feeds:

```
https://rssparam.<your-subdomain>.workers.dev/?rss=https://www.theverge.com/rss/index.xml&rss=https://news.ycombinator.com/rss&count=3
```

The `count` parameter controls how many items are shown per feed (default: 1).

## Development

See [Docs/Local-Setup.md](Docs/Local-Setup.md) for local `wrangler dev` setup and the dependency fix needed for newer `wrangler` versions.

## Deploy

Pushes to `main` trigger `.github/workflows/deploy.yml`, which deploys to Cloudflare Workers using the repository secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
