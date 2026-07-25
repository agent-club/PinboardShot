import type { MetadataRoute } from "next";
import { absoluteUrl, localeSeo, releaseIsoDate } from "./seo";

const languageAlternates = {
  languages: {
    "zh-CN": absoluteUrl(localeSeo.zh.path),
    en: absoluteUrl(localeSeo.en.path),
    "x-default": absoluteUrl("/"),
  },
};

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date(releaseIsoDate());

  return [
    {
      url: absoluteUrl("/"),
      lastModified,
      changeFrequency: "weekly",
      priority: 1,
      alternates: languageAlternates,
    },
    {
      url: absoluteUrl("/zh"),
      lastModified,
      changeFrequency: "weekly",
      priority: 0.9,
      alternates: languageAlternates,
    },
    {
      url: absoluteUrl("/en"),
      lastModified,
      changeFrequency: "weekly",
      priority: 0.9,
      alternates: languageAlternates,
    },
    {
      url: absoluteUrl("/privacy"),
      lastModified,
      changeFrequency: "monthly",
      priority: 0.6,
    },
  ];
}
