import assert from "node:assert/strict";
import test from "node:test";
import currentRelease from "../content/current-release.json" with { type: "json" };

async function render(path = "/", accept = "text/html") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`https://pinboardshot.example${path}`, {
      headers: { accept },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the PinboardShot download page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>PinboardShot - Mac 截图、标注与贴图工具<\/title>/i);
  assert.match(html, /<meta name="robots" content="index, follow"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="zh-CN" href="http:\/\/localhost:3000\/zh"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="en" href="http:\/\/localhost:3000\/en"\/>/i);
  assert.match(html, new RegExp(`href="${currentRelease.downloads.dmg.url.replaceAll(".", "\\.")}"`, "i"));
  assert.match(html, new RegExp(`href="${currentRelease.releaseUrl.replaceAll(".", "\\.")}"`, "i"));
  assert.match(html, /href="https:\/\/github\.com\/agent-club\/PinboardShot"/i);
  assert.doesNotMatch(html, /Not notarized|未经 Apple 公证/i);
  assert.ok(html.includes(currentRelease.version));
  assert.match(html, /Your screenshots stay|你的截图/);
  assert.match(html, /href="\/privacy"/i);
  assert.match(html, /AI 生成的示意图|AI-generated illustrative assets/i);
  assert.match(html, /Apple Inc\./i);
  assert.match(html, /application\/ld\+json/i);
  assert.match(html, /SoftwareApplication/i);
  assert.match(html, /FAQPage/i);
  assert.doesNotMatch(html, /Snipaste|ShareX/i);
});

test("server-renders the localized English page", async () => {
  const response = await render("/en");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>PinboardShot - Native Screenshot, Annotation, and Screen Pinning for Mac<\/title>/i);
  assert.match(html, /<main lang="en">/i);
  assert.match(html, /Frequently Asked Questions/);
  assert.match(html, /Privacy choices/);
  assert.doesNotMatch(html, /Snipaste|ShareX/i);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/en"/i);
});

test("server-renders the privacy policy", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Privacy Policy - PinboardShot<\/title>/i);
  assert.match(html, /Last updated:<\/strong>\s*(?:<!-- -->)?July 24, 2026/i);
  assert.match(html, /最后更新：<\/strong>\s*(?:<!-- -->)?2026 年 7 月 24 日/i);
  assert.match(html, /does not include analytics or advertising SDKs/i);
  assert.match(html, /AI-generated illustrative assets/i);
});

test("serves robots and sitemap for search crawlers", async () => {
  const robots = await render("/robots.txt", "text/plain");
  assert.equal(robots.status, 200);
  assert.match(robots.headers.get("content-type") ?? "", /^text\/plain\b/i);
  const robotsText = await robots.text();
  assert.match(robotsText, /User-Agent: OAI-SearchBot\s+Allow: \//i);
  assert.match(robotsText, /User-Agent: GPTBot\s+Disallow: \//i);
  assert.match(robotsText, /Sitemap: https:\/\/pinboardshot\.agentclub\.dev\/sitemap\.xml/i);

  const sitemap = await render("/sitemap.xml", "application/xml");
  assert.equal(sitemap.status, 200);
  assert.match(sitemap.headers.get("content-type") ?? "", /^application\/xml\b/i);
  const sitemapXml = await sitemap.text();
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/<\/loc>/i);
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/zh<\/loc>/i);
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/en<\/loc>/i);
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/privacy<\/loc>/i);
  assert.doesNotMatch(sitemapXml, /github\.com\/agent-club\/PinboardShot\/releases/i);
});
