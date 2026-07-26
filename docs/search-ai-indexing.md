# Search and AI Indexing Runbook

Use this checklist after publishing website or release changes that should be discoverable by search engines and AI answer systems.

## Canonical URLs

- Website: https://pinboardshot.agentclub.dev
- Chinese page: https://pinboardshot.agentclub.dev/zh
- English page: https://pinboardshot.agentclub.dev/en
- Sitemap: https://pinboardshot.agentclub.dev/sitemap.xml
- AI summary: https://pinboardshot.agentclub.dev/llms.txt
- GitHub repository: https://github.com/agent-club/PinboardShot

## Search Console Submission

Google Search Console:

1. Open the verified `pinboardshot.agentclub.dev` property.
2. Submit `https://pinboardshot.agentclub.dev/sitemap.xml` under Sitemaps.
3. Use URL Inspection for `/`, `/zh`, `/en`, `/privacy`, and `/llms.txt`.
4. Request indexing for any page that is not already indexed.

Bing Webmaster Tools:

1. Open the verified `pinboardshot.agentclub.dev` site.
2. Submit `https://pinboardshot.agentclub.dev/sitemap.xml` under Sitemaps.
3. Use URL Inspection for `/`, `/zh`, `/en`, `/privacy`, and `/llms.txt`.
4. Request indexing for pages that are missing from the index.

## Crawler Access Checks

The site should return `200` for public pages and expose crawl hints:

```bash
curl -I https://pinboardshot.agentclub.dev/en
curl https://pinboardshot.agentclub.dev/robots.txt
curl https://pinboardshot.agentclub.dev/sitemap.xml
curl https://pinboardshot.agentclub.dev/llms.txt
```

`robots.txt` should explicitly allow search and user-triggered AI retrieval crawlers while keeping training crawler policy intentional.

## Cloudflare Checks

In Cloudflare, inspect security events and HTTP request logs for these user agents:

- `OAI-SearchBot`
- `OAI-AdsBot`
- `ChatGPT-User`
- `Googlebot`
- `Bingbot`
- `Applebot`
- `PerplexityBot`
- `Perplexity-User`

Check for `403`, challenge, bot fight mode, managed challenge, WAF block, and `429` rate limit events. If legitimate crawlers are blocked, create the narrowest allow rule possible for the affected user agent and path.

## GitHub Signals

- Keep the repository homepage set to `https://pinboardshot.agentclub.dev`.
- Keep the README top section linked to the official website.
- Keep each GitHub Release body linked to the official website near the top.
- Keep repository topics aligned with the product, such as `macos`, `screenshot`, `annotation`, `pinboard`, `swift`, and `appkit`.

## External Entrances

Prioritize public pages that search engines already trust:

- GitHub README and Releases.
- Product Hunt launch page.
- Relevant Awesome lists.
- A short blog post or changelog page linking to the canonical website.
- Community posts that describe PinboardShot as a macOS screenshot, annotation, and screen pinning app.

Avoid duplicate landing pages that make a different URL look canonical.
