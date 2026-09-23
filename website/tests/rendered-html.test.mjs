import assert from "node:assert/strict";
import test from "node:test";
import { runInNewContext } from "node:vm";
import currentRelease from "../content/current-release.json" with { type: "json" };

const googleTagId = "G-WDBY7TDB0R";
const privacyConsentStorageKey = "pinboardshot-privacy-consent-v1";
const contentPages = [
  { path: "/features/scrolling-screenshot", title: "Mac 滚动截图：手动控制、实时预览与本地拼接" },
  { path: "/features/screen-pinning", title: "Mac 贴图：把截图、剪贴板和图片留在工作区上方" },
  { path: "/features/local-ocr-history", title: "本地 OCR 截图历史：可搜索、可配置，也能彻底清理" },
  { path: "/use-cases/design-review", title: "用截图、贴图和本地比较完成一次设计评审" },
  { path: "/compare/pinboardshot-vs-shottr", title: "PinboardShot 与 Shottr：怎样选择 Mac 截图工具" },
  { path: "/compare/pinboardshot-vs-snipaste", title: "PinboardShot 与 Snipaste：Mac 贴图和截图工作流对比" },
  { path: "/compare/pinboardshot-vs-cleanshot-x", title: "PinboardShot 与 CleanShot X：本地截图工具还是完整内容套件" },
];

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

function extractAnalyticsBootstrap(html) {
  const marker = html.indexOf("window.localStorage.getItem");
  assert.ok(marker >= 0, "expected an inline analytics consent bootstrap");
  const openStart = html.lastIndexOf("<script", marker);
  const openEnd = html.indexOf(">", openStart);
  const closeStart = html.indexOf("</script", marker);
  const closeEnd = html.indexOf(">", closeStart);
  assert.ok(openStart >= 0 && openEnd < marker && closeStart > marker && closeEnd > closeStart);
  // Check the closing tag before executing the extracted script, including tags with whitespace.
  assert.equal(html.slice(closeStart + 2, closeEnd).trim().toLowerCase(), "script");
  return html.slice(openEnd + 1, closeStart);
}

function runAnalyticsBootstrap(source, savedPrivacyConsent, { throwOnRead = false } = {}) {
  const calls = [];
  const events = [];
  const appendedScripts = [];
  const window = {
    dataLayer: {
      push(args) {
        const call = Array.from(args);
        calls.push(call);
        events.push(`gtag:${call[0]}`);
      },
    },
    localStorage: {
      getItem(key) {
        assert.equal(key, privacyConsentStorageKey);
        if (throwOnRead) throw new Error("local storage unavailable");
        return savedPrivacyConsent;
      },
    },
  };
  const document = {
    createElement(tagName) {
      assert.equal(tagName, "script");
      return { tagName };
    },
    head: {
      appendChild(script) {
        appendedScripts.push(script);
        events.push("append:script");
      },
    },
  };

  runInNewContext(source, { document, window });

  return {
    appendedScripts,
    calls,
    events,
    window,
  };
}

test("extracts an inline script with whitespace before its closing bracket", () => {
  assert.equal(
    extractAnalyticsBootstrap('<script>window.localStorage.getItem("choice")</script >'),
    'window.localStorage.getItem("choice")',
  );
});

test("server-renders the PinboardShot download page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.equal(response.headers.get("cache-control"), "no-transform");

  const html = await response.text();
  assert.match(html, /<title>PinboardShot - Mac 截图标注与贴图 Pinboard 工具<\/title>/i);
  assert.match(html, /<meta name="description" content="PinboardShot 是免费开源的原生 macOS 截图、标注与贴图工具。支持区域\/窗口截图、马赛克文字箭头、跨桌面贴屏、鼠标穿透、本地历史和 Retina 到 8K 输出，无账号、无云同步。"/i);
  assert.match(html, /<meta name="keywords" content="[^"]*PinboardShot download[^"]*Shottr alternative[^"]*Mac 截图贴图[^"]*"/i);
  assert.ok(html.length > 10000);
  assert.match(html, /<meta name="robots" content="index, follow"\/>/i);
  assert.match(html, /<meta name="googlebot" content="index, follow, max-image-preview:large, max-snippet:-1"\/>/i);
  assert.match(html, /<link rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/?"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="zh-CN" href="https:\/\/pinboardshot\.agentclub\.dev\/zh"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="en" href="https:\/\/pinboardshot\.agentclub\.dev\/en"\/>/i);
  assert.match(html, /<link rel="alternate" hrefLang="x-default" href="https:\/\/pinboardshot\.agentclub\.dev\/?"\/>/i);
  assert.match(html, /https:\/\/www\.googletagmanager\.com\/gtag\/js\?id=G-WDBY7TDB0R/i);
  assert.match(html, /window\.gtag\('js', new Date\(\)\)/i);
  assert.match(html, /window\.gtag\('config', "G-WDBY7TDB0R"\)/i);
  assert.doesNotMatch(html, /allow_ad_personalization_signals/i);
  assert.match(html, /property="og:image" content="https:\/\/pinboardshot\.agentclub\.dev\/opengraph-image\.png"/i);
  assert.match(html, /name="twitter:image" content="https:\/\/pinboardshot\.agentclub\.dev\/twitter-image\.png"/i);
  assert.match(html, /href="\/download"/i);
  assert.match(html, new RegExp(`href="${currentRelease.releaseUrl.replaceAll(".", "\\.")}"`, "i"));
  assert.match(html, /href="https:\/\/github\.com\/agent-club\/PinboardShot"/i);
  assert.doesNotMatch(html, /Not notarized|未经 Apple 公证/i);
  assert.ok(html.includes(currentRelease.version));
  assert.match(html, /Remote OCR is your choice|远程 OCR 由你决定/);
  assert.match(html, /href="\/privacy"/i);
  assert.match(html, /自有照片与界面示意素材|owned photos and interface mockups/i);
  assert.match(html, /Apple Inc\./i);
  assert.match(html, /application\/ld\+json/i);
  assert.match(html, /SoftwareApplication/i);
  assert.match(html, /Product/i);
  assert.match(html, /FAQPage/i);
  assert.match(html, /BreadcrumbList/i);
  for (const page of contentPages) assert.match(html, new RegExp(`href="${page.path}"`, "i"));
  assert.doesNotMatch(html, /ShareX/i);

  const text = visibleText(html);
  assert.ok(text.length > 3000);
  assert.match(text, /原生 macOS 截图、标注与贴图工具/);
  assert.match(text, /下载 DMG/);

  const structuredData = extractStructuredData(html);
  const software = structuredData.find((entry) => entry["@type"] === "SoftwareApplication");
  assert.equal(software.name, "PinboardShot");
  assert.equal(software.description, "PinboardShot 是免费开源的原生 macOS 截图、标注与贴图工具。支持区域/窗口截图、马赛克文字箭头、跨桌面贴屏、鼠标穿透、本地历史和 Retina 到 8K 输出，无账号、无云同步。");
  assert.equal(software.operatingSystem, "macOS 14 or later");
  assert.equal(software.applicationCategory, "ProductivityApplication");
  assert.equal(software.downloadUrl, "https://pinboardshot.agentclub.dev/download");
  assert.equal(software.softwareVersion, currentRelease.version);
});

test("restores an analytics opt-out before loading Google tag on every page", async () => {
  for (const path of ["/", "/zh", "/en", "/privacy", ...contentPages.map((page) => page.path)]) {
    const response = await render(path);
    assert.equal(response.status, 200);
    const html = await response.text();
    const bootstrap = extractAnalyticsBootstrap(html);

    assert.ok(
      bootstrap.indexOf("window.localStorage.getItem") < bootstrap.indexOf("document.createElement('script')"),
      `${path} should restore consent before creating the Google tag loader`,
    );

    const { appendedScripts, calls, events, window } = runAnalyticsBootstrap(bootstrap, "essential");
    assert.equal(window[`ga-disable-${googleTagId}`], true);
    assert.deepEqual(calls.map(([command]) => command), ["consent", "js", "config"]);
    assert.equal(calls[0][1], "default");
    assert.equal(calls[0][2].analytics_storage, "denied");
    assert.equal(calls[2][1], googleTagId);
    assert.deepEqual(events, ["gtag:consent", "gtag:js", "gtag:config", "append:script"]);
    assert.deepEqual(appendedScripts, [
      {
        async: true,
        src: `https://www.googletagmanager.com/gtag/js?id=${googleTagId}`,
        tagName: "script",
      },
    ]);
  }
});

test("server-renders citeable feature, use-case, and comparison pages", async () => {
  for (const page of contentPages) {
    const response = await render(page.path);
    assert.equal(response.status, 200, page.path);
    assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
    assert.equal(response.headers.get("cache-control"), "no-transform");

    const html = await response.text();
    assert.match(html, /<html lang="zh-CN">/i);
    assert.ok(html.includes(page.title), `${page.path} should render its H1`);
    assert.match(html, new RegExp(`rel="canonical" href="https:\/\/pinboardshot\\.agentclub\\.dev${page.path}"`, "i"));
    assert.match(html, /type="application\/ld\+json"/i);
    assert.match(html, /Article/i);
    assert.match(html, /BreadcrumbList/i);
    assert.match(html, /来源与核对口径/);
    assert.match(html, /事实核对/);

    const text = visibleText(html);
    assert.ok(text.length > 1100, `${page.path} should contain substantial visible copy`);
    const structuredData = extractStructuredData(html);
    const article = structuredData.find((entry) => entry["@type"] === "Article");
    assert.equal(article.headline, page.title);
    assert.equal(article.inLanguage, "zh-CN");
    assert.ok(Array.isArray(article.citation) && article.citation.length >= 3);
  }

  for (const path of ["/features/not-a-real-page", "/use-cases/not-a-real-page", "/compare/not-a-real-page"]) {
    assert.equal((await render(path)).status, 404, `${path} should not resolve`);
  }
});

test("keeps the documented analytics default for non-opt-out states", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  const bootstrap = extractAnalyticsBootstrap(await response.text());

  for (const savedPrivacyConsent of ["accepted", null, "", "unexpected"]) {
    const { appendedScripts, calls, events, window } = runAnalyticsBootstrap(bootstrap, savedPrivacyConsent);
    assert.equal(Object.hasOwn(window, `ga-disable-${googleTagId}`), false);
    assert.deepEqual(calls.map(([command]) => command), ["js", "config"]);
    assert.equal(calls[1][1], googleTagId);
    assert.deepEqual(events, ["gtag:js", "gtag:config", "append:script"]);
    assert.equal(appendedScripts[0].src, `https://www.googletagmanager.com/gtag/js?id=${googleTagId}`);
  }

  const unavailableStorage = runAnalyticsBootstrap(bootstrap, null, { throwOnRead: true });
  assert.equal(Object.hasOwn(unavailableStorage.window, `ga-disable-${googleTagId}`), false);
  assert.deepEqual(unavailableStorage.calls.map(([command]) => command), ["js", "config"]);
  assert.deepEqual(unavailableStorage.events, ["gtag:js", "gtag:config", "append:script"]);
});

test("server-renders substantial localized Chinese HTML", async () => {
  const response = await render("/zh");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.equal(response.headers.get("cache-control"), "no-transform");

  const html = await response.text();
  assert.match(html, /<main lang="zh-CN">/i);
  assert.match(html, /<html lang="zh-CN">/i);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/zh"/i);

  const text = visibleText(html);
  assert.ok(text.length > 3000);
  assert.match(text, /截图，然后/);
  assert.match(text, /原生 macOS 截图、标注与贴图工具/);
  assert.match(text, /默认本机处理，\s*远程 OCR 由你决定/);
  assert.match(text, /PinboardShot 是什么？/);
});

test("language navigation exposes crawlable URLs before JavaScript runs", async () => {
  for (const path of ["/", "/zh", "/en"]) {
    const response = await render(path);
    assert.equal(response.status, 200);
    const html = await response.text();
    const languageSwitch = html.match(/<div class="language-switch"[^>]*>([\s\S]*?)<\/div>/)?.[1];
    assert.ok(languageSwitch, `${path} should expose language navigation`);
    assert.match(languageSwitch, /<a[^>]*href="\/zh"[^>]*hrefLang="zh-CN"[^>]*>中文<\/a>/i);
    assert.match(languageSwitch, /<a[^>]*href="\/en"[^>]*hrefLang="en"[^>]*>EN<\/a>/i);
    assert.doesNotMatch(languageSwitch, /<button\b/i);
    const selected = path === "/en" ? "en" : "zh";
    assert.match(languageSwitch, new RegExp(`<a[^>]*href="/${selected}"[^>]*aria-current="page"`, "i"));
  }
});

test("server-renders the localized English page", async () => {
  const response = await render("/en");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.equal(response.headers.get("cache-control"), "no-transform");

  const html = await response.text();
  assert.match(html, /<title>PinboardShot - Screenshot Annotation and Pinboard App for Mac<\/title>/i);
  assert.match(html, /<meta name="description" content="PinboardShot is a free, open-source macOS screenshot app for capture, annotation, and screen pinning. Keep references local with click-through pins, local history, and 8K export."/i);
  assert.match(html, /<html lang="en">/i);
  assert.match(html, /<main lang="en">/i);
  assert.match(html, /Frequently Asked Questions/);
  assert.match(html, /Privacy choices/);
  assert.doesNotMatch(html, /ShareX/i);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/en"/i);

  const text = visibleText(html);
  assert.ok(text.length > 3000);
  assert.match(text, /Capture it\. Keep it in sight\./);
  assert.match(text, /native capture, annotation, and pinboard tool for macOS/i);
  assert.match(text, /Local by default\. Remote OCR is your choice\./);
});

test("server-renders the privacy policy", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.equal(response.headers.get("cache-control"), "no-transform");

  const html = await response.text();
  assert.match(html, /<title>Privacy Policy - PinboardShot<\/title>/i);
  assert.match(html, /<html lang="en">/i);
  assert.match(html, /rel="canonical" href="https:\/\/pinboardshot\.agentclub\.dev\/privacy"/i);
  assert.match(html, /property="og:url" content="https:\/\/pinboardshot\.agentclub\.dev\/privacy"/i);
  assert.match(html, /property="og:locale" content="en_US"/i);
  assert.match(html, /Last updated:<\/strong>\s*(?:<!-- -->)?August 23, 2026/i);
  assert.match(html, /最后更新：<\/strong>\s*(?:<!-- -->)?2026 年 8 月 23 日/i);
  assert.match(html, /does not include analytics or advertising SDKs/i);
  assert.match(html, /remote OCR plugin/i);
  assert.match(html, /API Keys are stored in macOS Keychain/i);
  assert.match(html, /The website uses Google tag for basic visit measurement/i);
  assert.match(html, /Analytics storage is enabled by default/i);
  assert.match(html, /do not\s+(?:<!-- -->)?enable ad personalization/i);
  assert.match(html, /owned photos and interface mockups/i);
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
  for (const page of contentPages) {
    const matches = sitemapXml.match(new RegExp(`<loc>https:\/\/pinboardshot\\.agentclub\\.dev${page.path}<\\/loc>`, "gi")) ?? [];
    assert.equal(matches.length, 1, `${page.path} should appear in the sitemap exactly once`);
  }
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
  assert.match(text, /10–250 captures for 1–90 days/i);
  assert.doesNotMatch(text, /latest 50 captures/i);
  for (const page of contentPages) assert.ok(text.includes(`https://pinboardshot.agentclub.dev${page.path}`));
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
