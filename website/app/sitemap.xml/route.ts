import { absoluteUrl, localeSeo, releaseIsoDate } from "../seo";
import { CONTENT_PAGES } from "@/content/content-pages";

const languageAlternates = [
  ["zh-CN", absoluteUrl(localeSeo.zh.path)],
  ["en", absoluteUrl(localeSeo.en.path)],
  ["x-default", absoluteUrl("/")],
] as const;

type CrawlablePage = { path: string; alternates: boolean; lastModified: string };

const crawlablePages: readonly CrawlablePage[] = [
  { path: "/", alternates: true, lastModified: releaseIsoDate() },
  { path: localeSeo.zh.path, alternates: true, lastModified: releaseIsoDate() },
  { path: localeSeo.en.path, alternates: true, lastModified: releaseIsoDate() },
  { path: "/privacy", alternates: false, lastModified: "2026-08-23" },
  ...CONTENT_PAGES.map((page) => ({
    path: page.path,
    alternates: false,
    lastModified: page.lastReviewed,
  })),
];

function escapeXml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function renderUrlEntry(page: CrawlablePage) {
  const alternateLinks = page.alternates
    ? languageAlternates
        .map(([hreflang, href]) => `<xhtml:link rel="alternate" hreflang="${hreflang}" href="${escapeXml(href)}" />`)
        .join("\n")
    : "";

  return [
    "<url>",
    `<loc>${escapeXml(absoluteUrl(page.path))}</loc>`,
    alternateLinks,
    `<lastmod>${page.lastModified}</lastmod>`,
    "</url>",
  ]
    .filter(Boolean)
    .join("\n");
}

export function GET() {
  const body = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    crawlablePages.map(renderUrlEntry).join("\n"),
    "</urlset>",
    "",
  ].join("\n");

  return new Response(body, {
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
