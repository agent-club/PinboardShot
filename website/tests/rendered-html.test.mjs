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
  assert.match(html, /application\/ld\+json/i);
  assert.match(html, /SoftwareApplication/i);
  assert.match(html, /FAQPage/i);
  assert.match(html, /Snipaste Mac 替代/i);
});

test("server-renders the localized English page", async () => {
  const response = await render("/en");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>PinboardShot - Native Screenshot, Annotation, and Screen Pinning for Mac<\/title>/i);
  assert.match(html, /<main lang="en">/i);
  assert.match(html, /Frequently Asked Questions/);
  assert.match(html, /Snipaste alternative for Mac/);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/en"/i);
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
  assert.doesNotMatch(sitemapXml, /github\.com\/agent-club\/PinboardShot\/releases/i);
});
