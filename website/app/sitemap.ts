import type { MetadataRoute } from "next";
import { absoluteUrl, releaseIsoDate } from "./seo";

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
  ];
}
