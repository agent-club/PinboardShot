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

function visibleText(html) {
  return html
    .replace(/<head[\s\S]*?<\/head>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#x27;/g, "'")
    .replace(/<!-- -->/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function extractStructuredData(html) {
  const blocks = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/gi)];
  return blocks.flatMap(([, json]) => {
    const data = JSON.parse(json);
    return Array.isArray(data) ? data : [data];
  });
}

test("server-renders the PinboardShot download page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>PinboardShot - Mac 截图、标注与贴图工具<\/title>/i);
  assert.ok(html.length > 10000);
  assert.match(html, /<meta name="robots" content="index, follow"\/>/i);
  assert.match(html, /<meta name="googlebot" content="index, follow, max-image-preview:large, max-snippet:-1"\/>/i);
  assert.match(html, /<link rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="zh-CN" href="https:\/\/pinboardshot\.agentclub\.dev\/zh"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="en" href="https:\/\/pinboardshot\.agentclub\.dev\/en"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="x-default" href="https:\/\/pinboardshot\.agentclub\.dev\/"\/>/i);
  assert.match(html, /https:\/\/www\.googletagmanager\.com\/gtag\/js\?id=G-WDBY7TDB0R/i);
  assert.match(html, /window\["ga-disable-G-WDBY7TDB0R"\] = localStorage\.getItem\("pinboardshot-privacy-consent-v1"\) === "essential"/i);
  assert.match(html, /gtag\('js', new Date\(\)\)/i);
  assert.match(html, /gtag\('config', 'G-WDBY7TDB0R'/i);
  assert.match(html, /allow_ad_personalization_signals: false/i);
  assert.match(html, /property="og:image" content="https:\/\/pinboardshot\.agentclub\.dev\/opengraph-image\.png"/i);
  assert.match(html, /name="twitter:image" content="https:\/\/pinboardshot\.agentclub\.dev\/twitter-image\.png"/i);
  assert.match(html, /href="\/download"/i);
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
  assert.match(html, /Product/i);
  assert.match(html, /FAQPage/i);
  assert.match(html, /BreadcrumbList/i);
  assert.doesNotMatch(html, /Snipaste|ShareX/i);

  const text = visibleText(html);
  assert.ok(text.length > 3000);
  assert.match(text, /原生 macOS 截图、标注与贴图工具/);
  assert.match(text, /下载 DMG/);

  const structuredData = extractStructuredData(html);
  const software = structuredData.find((entry) => entry["@type"] === "SoftwareApplication");
  assert.equal(software.name, "PinboardShot");
  assert.equal(software.description, "PinboardShot 是原生 macOS 截图、标注与贴图工具。截图、标注、最近历史和偏好设置默认只保存在本机，支持跨桌面贴屏、透明度、鼠标穿透、Retina 到 8K 输出和应用内更新。");
  assert.equal(software.operatingSystem, "macOS 14 or later");
  assert.equal(software.applicationCategory, "ProductivityApplication");
  assert.equal(software.downloadUrl, "https://pinboardshot.agentclub.dev/download");
  assert.equal(software.softwareVersion, currentRelease.version);
});

test("server-renders substantial localized Chinese HTML", async () => {
  const response = await render("/zh");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<main lang="zh-CN">/i);
  assert.match(html, /<html lang="zh-CN">/i);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/zh"/i);

  const text = visibleText(html);
  assert.ok(text.length > 3000);
  assert.match(text, /截图，然后/);
  assert.match(text, /原生 macOS 截图、标注与贴图工具/);
  assert.match(text, /你的截图，\s*只留在你的 Mac/);
  assert.match(text, /PinboardShot 是什么？/);
});

test("server-renders the localized English page", async () => {
  const response = await render("/en");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>PinboardShot - Native Screenshot, Annotation, and Screen Pinning for Mac<\/title>/i);
  assert.match(html, /<html lang="en">/i);
  assert.match(html, /<main lang="en">/i);
  assert.match(html, /Frequently Asked Questions/);
  assert.match(html, /Privacy choices/);
  assert.doesNotMatch(html, /Snipaste|ShareX/i);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/en"/i);

  const text = visibleText(html);
  assert.ok(text.length > 3000);
  assert.match(text, /Capture it\. Keep it in sight\./);
  assert.match(text, /native capture, annotation, and pinboard tool for macOS/i);
  assert.match(text, /Your screenshots stay on your Mac\./);
});

test("server-renders the privacy policy", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Privacy Policy - PinboardShot<\/title>/i);
  assert.match(html, /<html lang="en">/i);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/privacy"/i);
  assert.match(html, /property="og:url" content="https:\/\/pinboardshot\.agentclub\.dev\/privacy"/i);
  assert.match(html, /property="og:locale" content="en_US"/i);
  assert.match(html, /Last updated:<\/strong>\s*(?:<!-- -->)?July 25, 2026/i);
  assert.match(html, /最后更新：<\/strong>\s*(?:<!-- -->)?2026 年 7 月 25 日/i);
  assert.match(html, /does not include analytics or advertising SDKs/i);
  assert.match(html, /The website uses Google tag for basic visit measurement/i);
  assert.match(html, /Analytics storage is enabled by default/i);
  assert.match(html, /do not\s+(?:<!-- -->)?enable ad personalization/i);
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
  assert.doesNotMatch(robotsText, /^Host:/im);

  const sitemap = await render("/sitemap.xml", "application/xml");
  assert.equal(sitemap.status, 200);
  assert.match(sitemap.headers.get("content-type") ?? "", /^application\/xml\b/i);
  assert.equal(sitemap.headers.get("cache-control"), "no-store");
  const sitemapXml = await sitemap.text();
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/<\/loc>/i);
  assert.match(sitemapXml, new RegExp(`<lastmod>${currentRelease.date.replaceAll(".", "-")}</lastmod>`, "i"));
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/zh<\/loc>/i);
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/en<\/loc>/i);
  assert.match(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/privacy<\/loc>/i);
  assert.match(sitemapXml, /<xhtml:link rel="alternate" hreflang="zh-CN" href="https:\/\/pinboardshot\.agentclub\.dev\/zh"\s*\/>/i);
  assert.match(sitemapXml, /<xhtml:link rel="alternate" hreflang="en" href="https:\/\/pinboardshot\.agentclub\.dev\/en"\s*\/>/i);
  assert.match(sitemapXml, /<xhtml:link rel="alternate" hreflang="x-default" href="https:\/\/pinboardshot\.agentclub\.dev\/"\s*\/>/i);
  assert.doesNotMatch(sitemapXml, /<changefreq>|<priority>/i);
  assert.doesNotMatch(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/download<\/loc>/i);
  assert.doesNotMatch(sitemapXml, /<loc>https:\/\/pinboardshot\.agentclub\.dev\/llms\.txt<\/loc>/i);
  assert.doesNotMatch(sitemapXml, /github\.com\/agent-club\/PinboardShot\/releases/i);
});

test("serves llms.txt for AI readers", async () => {
  const response = await render("/llms.txt", "text/plain");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/plain\b/i);

  const text = await response.text();
  assert.match(text, /^# PinboardShot/m);
  assert.match(text, /native macOS screenshot, annotation, and screen pinning app/i);
  assert.match(text, /## Features/i);
  assert.match(text, /## System Requirements/i);
  assert.match(text, /## Download/i);
  assert.match(text, /## Privacy Commitments/i);
  assert.match(text, /The Mac app has no account, no cloud sync, and no telemetry/i);
  assert.match(text, /Website access may be measured with Google tag/i);
  assert.match(text, /macOS 14 or later/i);
  assert.match(text, /GitHub Release/i);
  assert.match(text, new RegExp(currentRelease.version.replaceAll(".", "\\.")));
  assert.match(text, /https:\/\/pinboardshot\.agentclub\.dev\/download/i);
  assert.doesNotMatch(text, /sha256|edSignature|private key/i);
});

test("serves stable download and social asset aliases", async () => {
  const download = await render("/download");
  assert.equal(download.status, 302);
  assert.equal(download.headers.get("location"), currentRelease.downloads.dmg.url);
  assert.equal(download.headers.get("cache-control"), "no-store");

  const opengraph = await render("/opengraph-image.png", "image/png");
  assert.equal(opengraph.status, 308);
  assert.equal(opengraph.headers.get("location"), "https://pinboardshot.example/og.png");
  assert.match(opengraph.headers.get("cache-control") ?? "", /s-maxage=86400/);

  const twitter = await render("/twitter-image.png", "image/png");
  assert.equal(twitter.status, 308);
  assert.equal(twitter.headers.get("location"), "https://pinboardshot.example/og.png");

  const appleTouchIcon = await render("/apple-touch-icon.png", "image/png");
  assert.equal(appleTouchIcon.status, 308);
  assert.equal(appleTouchIcon.headers.get("location"), "https://pinboardshot.example/apple-icon.png");
});
