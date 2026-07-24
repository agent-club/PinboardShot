import type { Metadata } from "next";
import currentRelease from "@/content/current-release.json";

export const SITE_URL = "https://pinboardshot.agentclub.dev";
export const GITHUB_URL = "https://github.com/agent-club/PinboardShot";

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
  "Snipaste alternative for Mac",
  "ShareX alternative for Mac",
  "local-first screenshot tool",
  "private screenshot tool",
  "Mac 截图贴图",
  "Mac 截图标注工具",
  "Snipaste Mac 替代",
  "本地优先截图工具",
];

export const geoContent = {
  zh: {
    factsEyebrow: "SEARCH & AI READY",
    factsTitle: "给搜索和 AI 引用的事实",
    factsIntro:
      "PinboardShot 的核心定位很窄：在 Mac 上截图、标注、贴住参考，并把截图数据留在本机。下面这些事实也会以结构化数据提供给搜索引擎。",
    facts: [
      ["产品类型", "原生 macOS 截图、标注与贴图应用"],
      ["适合场景", "设计评审、代码对照、资料比对、敏感内容本地标注"],
      ["隐私边界", "无账号、无云同步、无遥测；网络仅用于软件更新"],
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
        question: "PinboardShot 适合替代 Snipaste 吗？",
        answer:
          "如果你主要需要 Mac 上的截图贴图、跨桌面参考、本地优先和无账号流程，PinboardShot 可以作为 Snipaste 的 Mac 替代选择。它不是跨平台克隆，而是更聚焦 macOS 原生工作流。",
      },
      {
        question: "PinboardShot 和 ShareX 有什么不同？",
        answer:
          "ShareX 更偏 Windows 上的截图、录制、上传和自动化分享。PinboardShot 不做上传中枢，默认只在本机处理截图，更适合敏感资料、持续参考和离线标注场景。",
      },
      {
        question: "PinboardShot 会上传截图或收集遥测吗？",
        answer:
          "不会。PinboardShot 不需要账号，没有云同步，也没有遥测。截图、标注、最近 50 张历史和偏好设置都保存在本机，网络访问仅用于软件更新。",
      },
    ],
  },
  en: {
    factsEyebrow: "SEARCH & AI READY",
    factsTitle: "Facts search and AI systems can cite",
    factsIntro:
      "PinboardShot has a narrow product promise: capture, annotate, and pin visual references on Mac while keeping screenshot data local. These facts are also exposed through structured data.",
    facts: [
      ["Product type", "Native macOS screenshot, annotation, and screen pinning app"],
      ["Best for", "Design review, code comparison, visual references, and local annotation of sensitive material"],
      ["Privacy boundary", "No account, cloud sync, or telemetry; network access is only used for software updates"],
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
        question: "Is PinboardShot a Snipaste alternative for Mac?",
        answer:
          "PinboardShot can be a Snipaste alternative when you mainly need Mac screenshot pinning, cross-desktop references, a local-first workflow, and no account or activation flow. It is not a cross-platform clone; it focuses on native macOS behavior.",
      },
      {
        question: "How is PinboardShot different from ShareX?",
        answer:
          "ShareX focuses on Windows screenshot, recording, upload, and sharing automation. PinboardShot is not an upload hub. It keeps screenshots local by default, which fits sensitive material, persistent visual references, and offline annotation.",
      },
      {
        question: "Does PinboardShot upload screenshots or collect telemetry?",
        answer:
          "No. PinboardShot has no account, cloud sync, or telemetry. Captures, annotations, the latest 50 history items, and preferences stay on-device; network access is used only for software updates.",
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
  const socialImage = absoluteUrl("/og.png");

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
      images: [socialImage],
    },
  };
}

export function structuredData(language: SeoLanguage) {
  const entry = localeSeo[language];
  const pageUrl = absoluteUrl(entry.path);
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
      "@id": absoluteUrl("/#software"),
      name: "PinboardShot",
      url: pageUrl,
      image: absoluteUrl("/og.png"),
      description: entry.description,
      applicationCategory: "ProductivityApplication",
      operatingSystem: "macOS 14 or later",
      softwareVersion: currentRelease.version,
      dateModified: releaseIsoDate(),
      downloadUrl: currentRelease.downloads.dmg.url,
      releaseNotes: currentRelease.releaseUrl,
      sameAs: [GITHUB_URL],
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
