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
    title: "PinboardShot - Mac 截图标注与贴图 Pinboard 工具",
    description:
      "PinboardShot 是免费开源的原生 macOS 截图、标注与贴图工具。支持区域/窗口截图、马赛克文字箭头、跨桌面贴屏、鼠标穿透、本地历史和 Retina 到 8K 输出，无账号、无云同步。",
  },
  en: {
    path: "/en",
    htmlLang: "en",
    locale: "en_US",
    title: "PinboardShot - Screenshot Annotation and Pinboard App for Mac",
    description:
      "PinboardShot is a free, open-source macOS screenshot app for capture, annotation, and screen pinning. Keep references local with click-through pins, local history, and 8K export.",
  },
} as const;

export const seoKeywords = [
  "PinboardShot",
  "PinboardShot Mac",
  "PinboardShot download",
  "macOS screenshot tool",
  "Mac screenshot app",
  "Mac screenshot annotation",
  "Mac annotation tool",
  "screen pin tool for Mac",
  "Mac pinboard app",
  "local-first screenshot tool",
  "private screenshot tool",
  "open source screenshot app",
  "free Mac screenshot tool",
  "Shottr alternative",
  "CleanShot X alternative",
  "Xnip alternative",
  "pin screenshot on Mac",
  "Mac 截图贴图",
  "Mac 截图标注工具",
  "Mac 截图工具",
  "Mac 贴图工具",
  "截图钉板",
  "贴屏工具",
  "本地优先截图工具",
  "Mac 本地截图工具",
  "免费 Mac 截图工具",
  "开源 Mac 截图工具",
  "macOS screen pinning",
  "private Mac screenshot app",
];

export const geoContent = {
  zh: {
    factsEyebrow: "SEARCH & AI READY",
    factsTitle: "给搜索和 AI 引用的事实",
    factsIntro:
      "PinboardShot 的核心定位很窄：在 Mac 上截图、标注、贴住参考，并默认在本机处理截图数据。远程 OCR 只有在用户配置插件并主动框选区域后才会运行。官网使用 Google tag 做基础访问衡量，并提供隐私选择。下面这些事实也会以结构化数据提供给搜索引擎。",
    facts: [
      ["产品类型", "原生 macOS 截图、标注与贴图应用"],
      ["适合场景", "设计评审、代码对照、资料比对、敏感内容本地标注"],
      ["隐私边界", "Mac 应用无账号、无云同步、无遥测；远程 OCR 默认关闭且只发送主动框选区域"],
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
          "不会。PinboardShot 不是上传或同步工具。截图、标注、最近历史和偏好设置默认保存在本机。只有用户明确配置远程 OCR 插件并主动框选 OCR 区域时，该区域才会发送到指定服务。",
      },
      {
        question: "PinboardShot 会上传截图或收集遥测吗？",
        answer:
          "PinboardShot 不收集遥测，也不会自动上传截图。Mac 应用不需要账号，没有云同步；只有用户明确配置远程 OCR 插件并主动使用 OCR 工具时，所选图片区域才会发送到指定服务。历史索引和智能脱敏始终在本机完成。官网使用 Google tag 做基础访问衡量。",
      },
      {
        question: "已经授权但仍然不能截图怎么办？",
        answer:
          "请在 PinboardShot 设置中检查屏幕录制权限状态，打开系统设置确认授权，然后完全退出并重新启动 PinboardShot。App 只读取截图所需的屏幕像素，不会录制音频。",
      },
      {
        question: "开启鼠标穿透后如何找回贴图？",
        answer:
          "打开菜单栏中的贴图管理并选择恢复全部鼠标交互。也可以在单张贴图的右键菜单中关闭鼠标穿透。",
      },
      {
        question: "滚动截图拼接不正确怎么办？",
        answer:
          "请放慢滚动速度，每次保留一部分上一屏内容，并避开视频、动画或会变化的悬浮栏。右侧实时预览可帮助你在完成前检查结果。",
      },
    ],
  },
  en: {
    factsEyebrow: "SEARCH & AI READY",
    factsTitle: "Facts search and AI systems can cite",
    factsIntro:
      "PinboardShot has a narrow product promise: capture, annotate, and pin visual references on Mac while keeping screenshot data local by default. Remote OCR runs only after the user configures a plugin and actively selects a region. The website uses Google tag for basic visit measurement and offers privacy choices. These facts are also exposed through structured data.",
    facts: [
      ["Product type", "Native macOS screenshot, annotation, and screen pinning app"],
      ["Best for", "Design review, code comparison, visual references, and local annotation of sensitive material"],
      ["Privacy boundary", "The Mac app has no account, cloud sync, or telemetry; remote OCR is off by default and sends only actively selected regions"],
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
          "No. PinboardShot is not an upload or sync tool. Captures, annotations, recent history, and preferences stay local by default. Only a region actively selected for OCR is sent after the user configures a remote OCR plugin.",
      },
      {
        question: "Does PinboardShot upload screenshots or collect telemetry?",
        answer:
          "PinboardShot collects no telemetry and never uploads captures automatically. The Mac app has no account or cloud sync. A selected image region is sent only when the user configures a remote OCR plugin and actively uses the OCR tool; history indexing and smart redaction stay on-device. The website uses Google tag for basic visit measurement.",
      },
      {
        question: "What if capture still fails after I grant permission?",
        answer:
          "Check Screen Recording permission in PinboardShot Settings, confirm access in System Settings, then quit and restart PinboardShot. The app reads only the screen pixels needed for captures and does not record audio.",
      },
      {
        question: "How do I recover a click-through pin?",
        answer:
          "Open Pin Management from the menu bar and restore pointer interaction for all pins. You can also turn off click-through from an individual pin's context menu.",
      },
      {
        question: "What should I do when a scrolling capture does not stitch correctly?",
        answer:
          "Scroll more slowly, keep some content from the previous view visible, and avoid video, animation, or changing floating bars. Use the live preview to inspect the result before finishing.",
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
        "x-default": absoluteUrl("/"),
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
      url: absoluteUrl("/"),
      sameAs: [GITHUB_URL],
    },
    {
      "@context": "https://schema.org",
      "@type": "WebSite",
      "@id": absoluteUrl("/#website"),
      name: "PinboardShot",
      url: absoluteUrl("/"),
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
        "Area, display, window, scrolling, delayed, and repeat-region screenshot capture",
        "On-device OCR by default, optional remote OCR plugins, color picking, and local smart redaction",
        "Mosaic, pen, rectangle, ellipse, line, numbered step, highlight, arrow, and text annotation",
        "Floating pinned screenshots across macOS desktop spaces",
        "Opacity control, click-through, shadows, and bulk pin visibility",
        "Native Retina, 720p, 1080p, 2K, 4K, and 8K export",
        "Searchable local screenshot history and comparison boards",
        "URL scheme and macOS Shortcuts automation",
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
          item: absoluteUrl("/"),
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
