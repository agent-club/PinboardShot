import type { MetadataRoute } from "next";
import { DOWNLOAD_PATH, LLMS_PATH, absoluteUrl, releaseIsoDate } from "./seo";

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date(releaseIsoDate());

  return [
    {
      url: absoluteUrl("/"),
      lastModified,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: absoluteUrl("/zh"),
      lastModified,
      changeFrequency: "weekly",
      priority: 0.9,
    },
    {
      url: absoluteUrl("/en"),
      lastModified,
      changeFrequency: "weekly",
      priority: 0.9,
    },
    {
      url: absoluteUrl("/privacy"),
      lastModified,
      changeFrequency: "monthly",
      priority: 0.6,
    },
    {
      url: absoluteUrl(DOWNLOAD_PATH),
      lastModified,
      changeFrequency: "weekly",
      priority: 0.7,
    },
    {
      url: absoluteUrl(LLMS_PATH),
      lastModified,
      changeFrequency: "weekly",
      priority: 0.4,
    },
  ];
}
