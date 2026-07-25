import type { Metadata } from "next";
import currentRelease from "@/content/current-release.json";

export const SITE_URL = "https://pinboardshot.agentclub.dev";
export const GITHUB_URL = "https://github.com/agent-club/PinboardShot";
export const DOWNLOAD_PATH = "/download";
export const OPENGRAPH_IMAGE_PATH = "/opengraph-image.png";
export const TWITTER_IMAGE_PATH = "/twitter-image.png";
export const LLMS_PATH = "/llms.txt";
export const GOOGLE_TAG_ID = "G-WDBY7TDB0R";

export type SeoLanguage = "zh" | "en";

export const localeSeo = {
  zh: {
    path: "/zh",
    htmlLang: "zh-CN",
    locale: "zh_CN",
    title: "PinboardShot - Mac 截图、标注与贴图工具",
    description:
      "PinboardShot 是原生 macOS 截图、标注与贴图工具。截图、标注、最近历史和偏好设置默认只保存在本机，支持跨桌面贴屏、透明度、鼠标穿透、Retina 到 8K 输出和应用内更新。",
  },
  en: {
    path: "/en",
    htmlLang: "en",
    locale: "en_US",
    title: "PinboardShot - Native Screenshot, Annotation, and Screen Pinning for Mac",
    description:
      "PinboardShot is a native macOS screenshot, annotation, and screen pinning app. It keeps captures, annotations, recent history, and preferences local to your Mac, with pin controls, click-through, Retina to 8K export, and signed updates.",
  },
} as const;

export const seoKeywords = [
  "PinboardShot",
  "macOS screenshot tool",
  "Mac screenshot annotation",
  "screen pin tool for Mac",
  "local-first screenshot tool",
  "private screenshot tool",
  "Mac 截图贴图",
  "Mac 截图标注工具",
  "本地优先截图工具",
  "Mac 本地截图工具",
  "macOS screen pinning",
  "private Mac screenshot app",
];

export const geoContent = {
  zh: {
    factsEyebrow: "SEARCH & AI READY",
    factsTitle: "给搜索和 AI 引用的事实",
    factsIntro:
      "PinboardShot 的核心定位很窄：在 Mac 上截图、标注、贴住参考，并把截图数据留在本机。官网使用 Google tag 做基础访问衡量，并提供隐私选择。下面这些事实也会以结构化数据提供给搜索引擎。",
    facts: [
      ["产品类型", "原生 macOS 截图、标注与贴图应用"],
      ["适合场景", "设计评审、代码对照、资料比对、敏感内容本地标注"],
      ["隐私边界", "Mac 应用无账号、无云同步、无遥测；官网使用 Google tag 做基础访问衡量"],
      ["分发可信度", "Developer ID 签名，并通过 Apple 公证"],
    ],
    faqTitle: "常见问题",
    faqs: [
      {
        question: "PinboardShot 是什么？",
        answer:
          "PinboardShot 是一款原生 macOS 截图、标注与贴图工具。它可以截取区域、屏幕或窗口，添加马赛克、画笔、形状、箭头和文字，并把截图固定在桌面作为持续参考。",
      },
      {
        question: "PinboardShot 适合处理敏感资料吗？",
        answer:
          "PinboardShot 适合需要本地截图、标注和持续参考的敏感资料场景。Mac 应用不需要账号，不做云同步，也不包含遥测；截图数据默认留在你的 Mac 上。官网使用 Google tag 做基础访问衡量。",
      },
      {
        question: "PinboardShot 会把截图自动同步到云端吗？",
        answer:
          "不会。PinboardShot 不是上传或同步工具。截图、标注、最近历史和偏好设置都默认保存在本机，网络访问主要用于软件更新。",
      },
      {
        question: "PinboardShot 会上传截图或收集遥测吗？",
        answer:
          "不会。PinboardShot 的 Mac 应用不需要账号，没有云同步，也没有遥测。截图、标注、最近 50 张历史和偏好设置都保存在本机。官网使用 Google tag 做基础访问衡量。",
      },
    ],
  },
  en: {
    factsEyebrow: "SEARCH & AI READY",
    factsTitle: "Facts search and AI systems can cite",
    factsIntro:
      "PinboardShot has a narrow product promise: capture, annotate, and pin visual references on Mac while keeping screenshot data local. The website uses Google tag for basic visit measurement and offers privacy choices. These facts are also exposed through structured data.",
    facts: [
      ["Product type", "Native macOS screenshot, annotation, and screen pinning app"],
      ["Best for", "Design review, code comparison, visual references, and local annotation of sensitive material"],
      ["Privacy boundary", "The Mac app has no account, cloud sync, or telemetry; the website uses Google tag for basic visit measurement"],
      ["Distribution trust", "Developer ID signed and notarized by Apple"],
    ],
    faqTitle: "Frequently Asked Questions",
    faqs: [
      {
        question: "What is PinboardShot?",
        answer:
          "PinboardShot is a native macOS screenshot, annotation, and screen pinning app. It captures areas, displays, or windows, adds mosaic, pen, shape, arrow, highlight, and text annotations, and keeps screenshots floating as working references.",
      },
      {
        question: "Is PinboardShot suitable for sensitive material?",
        answer:
          "PinboardShot fits sensitive material workflows that need local capture, annotation, and persistent visual references. The Mac app does not require an account, does not provide cloud sync, and does not include telemetry; screenshot data stays on your Mac by default. The website uses Google tag for basic visit measurement.",
      },
      {
        question: "Does PinboardShot automatically sync screenshots to the cloud?",
        answer:
          "No. PinboardShot is not an upload or sync tool. Captures, annotations, recent history, and preferences stay local by default, and network access is centered on software updates.",
      },
      {
        question: "Does PinboardShot upload screenshots or collect telemetry?",
        answer:
          "No. The PinboardShot Mac app has no account, cloud sync, or telemetry. Captures, annotations, the latest 50 history items, and preferences stay on-device. The website uses Google tag for basic visit measurement.",
      },
    ],
  },
} as const;

export function absoluteUrl(path = "/") {
  return new URL(path, SITE_URL).toString();
}

export function releaseIsoDate() {
  return currentRelease.date.replaceAll(".", "-");
}

export function localizedMetadata(language: SeoLanguage): Metadata {
  const entry = localeSeo[language];
  const canonical = absoluteUrl(entry.path);
  const socialImage = absoluteUrl(OPENGRAPH_IMAGE_PATH);
  const twitterImage = absoluteUrl(TWITTER_IMAGE_PATH);

  return {
    title: entry.title,
    description: entry.description,
    keywords: seoKeywords,
    alternates: {
      canonical,
      languages: {
        "zh-CN": absoluteUrl(localeSeo.zh.path),
        en: absoluteUrl(localeSeo.en.path),
        "x-default": SITE_URL,
      },
    },
    openGraph: {
      title: entry.title,
      description: entry.description,
      url: canonical,
      siteName: "PinboardShot",
      type: "website",
      locale: entry.locale,
      alternateLocale: language === "zh" ? ["en_US"] : ["zh_CN"],
      images: [{ url: socialImage, width: 1792, height: 1024, alt: "PinboardShot for macOS" }],
    },
    twitter: {
      card: "summary_large_image",
      title: entry.title,
      description: entry.description,
      images: [twitterImage],
    },
  };
}

export function structuredData(language: SeoLanguage) {
  const entry = localeSeo[language];
  const pageUrl = absoluteUrl(entry.path);
  const softwareId = absoluteUrl("/#software");
  const productId = absoluteUrl("/#product");
  const faqs = geoContent[language].faqs;

  return [
    {
      "@context": "https://schema.org",
      "@type": "Organization",
      "@id": absoluteUrl("/#organization"),
      name: "PinboardShot",
      url: SITE_URL,
      sameAs: [GITHUB_URL],
    },
    {
      "@context": "https://schema.org",
      "@type": "WebSite",
      "@id": absoluteUrl("/#website"),
      name: "PinboardShot",
      url: SITE_URL,
      inLanguage: [localeSeo.zh.htmlLang, localeSeo.en.htmlLang],
    },
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      "@id": softwareId,
      name: "PinboardShot",
      url: pageUrl,
      image: absoluteUrl(OPENGRAPH_IMAGE_PATH),
      description: entry.description,
      applicationCategory: "ProductivityApplication",
      operatingSystem: "macOS 14 or later",
      softwareVersion: currentRelease.version,
      dateModified: releaseIsoDate(),
      downloadUrl: absoluteUrl(DOWNLOAD_PATH),
      installUrl: absoluteUrl(DOWNLOAD_PATH),
      releaseNotes: currentRelease.releaseUrl,
      softwareRequirements: "macOS 14 or later",
      isAccessibleForFree: true,
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
        availability: "https://schema.org/InStock",
        url: absoluteUrl(DOWNLOAD_PATH),
      },
      featureList: [
        "Area, display, window, and delayed screenshot capture",
        "Mosaic, pen, rectangle, highlight, arrow, and text annotation",
        "Floating pinned screenshots across macOS desktop spaces",
        "Opacity control, click-through, shadows, and bulk pin visibility",
        "Native Retina, 720p, 1080p, 2K, 4K, and 8K export",
        "Local screenshot history and preferences",
      ],
      sameAs: [GITHUB_URL],
    },
    {
      "@context": "https://schema.org",
      "@type": "Product",
      "@id": productId,
      name: "PinboardShot",
      image: absoluteUrl(OPENGRAPH_IMAGE_PATH),
      description: entry.description,
      brand: {
        "@type": "Brand",
        name: "PinboardShot",
      },
      category: "macOS screenshot and annotation software",
      url: pageUrl,
      isRelatedTo: {
        "@id": softwareId,
      },
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
        availability: "https://schema.org/InStock",
        url: absoluteUrl(DOWNLOAD_PATH),
      },
      additionalProperty: geoContent[language].facts.map(([name, value]) => ({
        "@type": "PropertyValue",
        name,
        value,
      })),
      sameAs: [GITHUB_URL],
    },
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      "@id": `${pageUrl}#breadcrumb`,
      itemListElement: [
        {
          "@type": "ListItem",
          position: 1,
          name: "PinboardShot",
          item: SITE_URL,
        },
        {
          "@type": "ListItem",
          position: 2,
          name: language === "zh" ? "中文" : "English",
          item: pageUrl,
        },
      ],
    },
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      "@id": `${pageUrl}#faq`,
      mainEntity: faqs.map((faq) => ({
        "@type": "Question",
        name: faq.question,
        acceptedAnswer: {
          "@type": "Answer",
          text: faq.answer,
        },
      })),
    },
  ];
}
