"use client";

import { useEffect, useState } from "react";
import currentRelease from "@/content/current-release.json";

type Language = "zh" | "en";

const releaseUrl = currentRelease.releaseUrl;
const primaryDownloadUrl = currentRelease.downloads.dmg.url;
const githubUrl = "https://github.com/agent-club/PinboardShot";

function GitHubIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M12 2C6.48 2 2 6.59 2 12.25c0 4.53 2.87 8.37 6.84 9.73.5.09.68-.22.68-.49 0-.24-.01-1.05-.01-1.9-2.78.62-3.37-1.21-3.37-1.21-.45-1.19-1.11-1.5-1.11-1.5-.91-.64.07-.63.07-.63 1 .07 1.53 1.06 1.53 1.06.89 1.56 2.34 1.11 2.91.85.09-.66.35-1.11.63-1.37-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05A9.33 9.33 0 0 1 12 6.97c.85 0 1.7.12 2.5.35 1.9-1.33 2.74-1.05 2.74-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.79-4.57 5.05.36.32.68.94.68 1.9 0 1.37-.01 2.47-.01 2.81 0 .27.18.59.69.49A10.18 10.18 0 0 0 22 12.25C22 6.59 17.52 2 12 2Z"
      />
    </svg>
  );
}

const copy = {
  zh: {
    nav: { features: "功能", workflow: "使用方式", compare: "差异", privacy: "隐私", changelog: "更新日志", download: "下载" },
    eyebrow: "为 macOS 精心打造",
    title: "截图，然后\n留在眼前",
    intro: "原生 macOS 截图、标注与贴图工具，从框选到马赛克、文字和贴屏，全程只在本机完成",
    download: "下载 DMG",
    learn: "看看它能做什么",
    requirement: "macOS 14+ · Universal · Apple Silicon 与 Intel · Developer ID 签名 · Apple 公证",
    distributionEyebrow: "正式公开分发",
    distributionTitle: "已签名，\n也已通过 Apple 公证",
    distributionBody: "PinboardShot 0.5.7 是首个 Developer ID 签名并通过 Apple 公证的公开版本；新用户可下载 DMG 手动安装，已安装用户可继续使用应用内更新",
    distributionSteps: [
      "下载 DMG 并打开安装窗口",
      "将 PinboardShot 拖入“应用程序”文件夹",
      "首次启动后按提示授予屏幕与系统音频录制权限",
    ],
    checksum: "查看 SHA-256",
    source: "查看 GitHub Release",
    repo: "GitHub 仓库",
    previewBadge: "Developer ID · Apple 公证",
    pinned: "已贴到桌面",
    selection: "区域截图",
    toolbar: "标注 · 复制 · 贴屏",
    featuresEyebrow: "从捕捉到标注，一次完成",
    featuresTitle: "能力更完整，\n操作依然简单",
    features: [
      ["灵活截图", "区域、当前屏幕、光标所在窗口，以及 3 秒延迟截图"],
      ["即时标注", "马赛克、画笔、矩形、高亮、箭头与可再次编辑的文字"],
      ["选区微调", "框选后继续调整八个控制点，双击即可快速复制"],
      ["清晰度控制", "支持原生 Retina、720p、1080p、2K、4K 与 8K 输出"],
      ["直接贴屏", "截图后立即固定在桌面，并可同时保留任意多张贴图"],
      ["贴图控制", "等比缩放、透明度、鼠标穿透、阴影和批量显隐"],
      ["本地历史", "最近 50 张截图保存在本机，查看尺寸并随时重新贴回"],
      ["快捷键中心", "同一动作可绑定多组快捷键，并自动检查组合冲突"],
      ["原生多语言", "跟随系统，或切换简体中文、繁体中文和英文"],
    ],
    workflowEyebrow: "捕捉 → 标注 → 贴屏 → 继续工作",
    workflowTitle: "需要的信息，\n当场变成参考",
    workflow: [
      ["01", "捕捉", "框选区域，或直接截取屏幕与窗口；选区可继续微调"],
      ["02", "标注", "用马赛克、画笔、形状、箭头和文字就地说明重点"],
      ["03", "贴住", "复制到剪贴板，或让结果悬浮在所有桌面空间最前方"],
      ["04", "继续", "缩放、调整透明度、开启穿透，保持工作流不断"],
    ],
    demoHint: "自动播放 · 点击步骤可跳转",
    pinEyebrow: "贴图之后，依然轻盈",
    pinTitle: "参考资料，\n不再挡住工作",
    pinBody: "多张贴图可以同时悬浮在所有桌面空间，移动、等比缩放、调节透明度或开启鼠标穿透，参考始终在场，操作始终顺手",
    pinStats: [["贴图数量", "不限"], ["透明度", "20—100%"], ["桌面空间", "全部"]],
    pinStatus: ["正在框选", "正在标注", "已贴到桌面", "鼠标穿透已开启"],
    comparisonEyebrow: "DIFFERENT BY CHOICE",
    comparisonTitle: "不是更多按钮，\n而是更清楚的取舍",
    comparisonBody: "Snipaste 和 ShareX 都很强，但它们解决的问题不同。PinboardShot 选择更窄的 Mac 工作流：截图、标注、贴住参考，并把外部网络和数据流转保持到最低。",
    comparisonCards: [
      {
        name: "Snipaste",
        label: "跨平台截图贴图",
        strength: "成熟、快捷、贴图操作丰富，适合熟悉 F1/F3 工作流的多平台用户。",
        difference: "PinboardShot 更聚焦 macOS 原生体验、无账号无激活链路、无遥测，以及截图分发后的离线隐形水印。",
      },
      {
        name: "ShareX",
        label: "Windows 自动化分享",
        strength: "面向高级用户，覆盖录屏、OCR、上传目的地、短链和自定义工作流。",
        difference: "PinboardShot 不做上传中枢，默认只在本机处理截图，更适合敏感资料和持续参考场景。",
      },
      {
        name: "PinboardShot",
        label: "Mac 本地参考流",
        strength: "原生 macOS、截图后即贴屏、跨桌面空间、透明度、鼠标穿透、Retina 到 8K 输出。",
        difference: "Developer ID 签名和 Apple 公证是可信分发基础；真正的差异是本地优先、贴屏参考和可选离线水印。",
      },
    ],
    comparisonSummary: ["Mac 原生", "无账号无遥测", "截图留在本机", "可选离线水印"],
    privacyEyebrow: "PRIVATE BY DESIGN",
    privacyTitle: "你的截图，\n只留在你的 Mac",
    privacyBody: "不需要账号，没有云同步，也没有遥测，截图、标注、最近 50 张历史和偏好设置都只在设备本地处理；网络仅用于软件更新，异常空白帧会被拒绝，不会覆盖上一份剪贴板内容",
    privacyPoints: ["仅更新访问网络", "零分析服务", "异常帧保护", "原生系统框架"],
    changelogEyebrow: "CHANGELOG",
    changelogTitle: "每次更新，\n都有迹可循",
    changelogBody: "这里展示 GitHub Release 中的版本要点，完整说明、兼容性和安装方式以对应 Release 记录为准",
    changelogLink: "查看完整 Release",
    releases: [
      {
        version: currentRelease.version,
        date: currentRelease.date,
        ...currentRelease.zh,
      },
      {
        version: "0.5.1",
        date: "2026.07.12",
        label: "历史版本",
        title: "离线隐形水印与更新设置",
        changes: [
          "新增可选的隐形水印，为新截图写入随机截图 ID 和校验信息",
          "水印记录可填写项目、接收方和自定义文案，相关信息只保存在本机",
          "新增隐形水印检测，支持常见重编码、缩放、JPEG 压缩和轻度裁剪场景",
          "新增自动更新检查开关和检查频率设置",
        ],
      },
      {
        version: "0.5.0",
        date: "2026.07.12",
        label: "首次发布",
        title: "安全更新与完整标注体验",
        changes: [
          "新增马赛克、画笔、矩形、高亮、箭头和可编辑文字标注",
          "新增简体中文、繁体中文和英文界面，并支持运行时切换",
          "新增截图启动动画与贴图阴影设置",
          "新增基于 Sparkle 的签名更新能力，网络仍仅用于软件更新",
        ],
      },
    ],
    ctaTitle: "把重要内容，留在眼前",
    ctaBody: "轻量、原生、专注，现在下载 PinboardShot",
    footer: "一个纯原生的 macOS 截图与贴图工具",
    copyright: "本地优先，由设计开始",
  },
  en: {
    nav: { features: "Features", workflow: "How it works", compare: "Compare", privacy: "Privacy", changelog: "Changelog", download: "Download" },
    eyebrow: "Crafted for macOS",
    title: "Capture it.\nKeep it in sight.",
    intro: "A native capture, annotation, and pinboard tool for macOS. From selection to markup and pinning, everything stays on your Mac.",
    download: "Download DMG",
    learn: "See what it can do",
    requirement: "macOS 14+ · Universal · Apple Silicon & Intel · Developer ID signed · Apple notarized",
    distributionEyebrow: "Public distribution",
    distributionTitle: "Signed,\nand notarized by Apple.",
    distributionBody: "PinboardShot 0.5.7 is the first public build signed with Developer ID and notarized by Apple. New users can install with the DMG, while existing users can continue to use the in-app updater.",
    distributionSteps: [
      "Download the DMG and open the installer window.",
      "Drag PinboardShot into the Applications folder.",
      "On first launch, grant Screen & System Audio Recording permission when prompted.",
    ],
    checksum: "View SHA-256",
    source: "View GitHub Release",
    repo: "GitHub repository",
    previewBadge: "Developer ID · Apple notarized",
    pinned: "Pinned to desktop",
    selection: "Area capture",
    toolbar: "Annotate · Copy · Pin",
    featuresEyebrow: "Capture and annotate in one pass",
    featuresTitle: "More capable.\nStill effortless.",
    features: [
      ["Flexible capture", "Grab an area, display, pointer window, or start a three-second delayed capture."],
      ["Instant annotation", "Use mosaic, pen, rectangle, highlight, arrow, and editable text tools."],
      ["Precise selection", "Refine a capture with eight resize handles, or double-click to copy instantly."],
      ["Output quality", "Choose Native Retina, 720p, 1080p, 2K, 4K, or 8K output."],
      ["Pin instantly", "Keep any capture on top and compare as many pinned references as you need."],
      ["Pin controls", "Resize proportionally, tune opacity, pass clicks through, toggle shadows, and hide in bulk."],
      ["Local history", "Keep the latest 50 captures on-device, inspect dimensions, and pin them again."],
      ["Shortcut center", "Assign multiple shortcuts to each action with built-in conflict detection."],
      ["Native languages", "Follow macOS or use Simplified Chinese, Traditional Chinese, and English."],
    ],
    workflowEyebrow: "Capture → Annotate → Pin → Keep moving",
    workflowTitle: "Turn a passing detail\ninto a working reference.",
    workflow: [
      ["01", "Capture", "Select an area, display, or window, then refine the selection if needed."],
      ["02", "Annotate", "Add mosaic, strokes, shapes, arrows, highlights, or editable text in place."],
      ["03", "Pin", "Copy the result or keep it floating across every desktop space."],
      ["04", "Continue", "Resize, tune opacity, or pass clicks through without losing focus."],
    ],
    demoHint: "Auto-playing · Select any step",
    pinEyebrow: "Lightweight after the capture, too",
    pinTitle: "References stay visible.\nYour work stays clear.",
    pinBody: "Keep as many pins as you need across every desktop space. Move, resize proportionally, tune opacity, or pass clicks through while the reference stays exactly where you need it.",
    pinStats: [["Pinned images", "Unlimited"], ["Opacity", "20—100%"], ["Desktop spaces", "All"]],
    pinStatus: ["Selecting area", "Annotating", "Pinned to desktop", "Click-through enabled"],
    comparisonEyebrow: "DIFFERENT BY CHOICE",
    comparisonTitle: "Not more buttons.\nClearer tradeoffs.",
    comparisonBody: "Snipaste and ShareX are both strong, but they solve different problems. PinboardShot chooses a narrower Mac workflow: capture, annotate, keep references visible, and keep network and data movement minimal.",
    comparisonCards: [
      {
        name: "Snipaste",
        label: "Cross-platform snip and pin",
        strength: "Mature, fast, and rich in pin controls for people who already rely on the F1/F3 workflow across platforms.",
        difference: "PinboardShot focuses on native macOS behavior, no account or license-activation flow, no telemetry, and offline invisible watermarking after screenshots leave your desk.",
      },
      {
        name: "ShareX",
        label: "Windows sharing automation",
        strength: "Built for power users with recording, OCR, upload destinations, short links, and custom workflows.",
        difference: "PinboardShot is not an upload hub. Screenshots stay local by default, which fits sensitive material and persistent reference work.",
      },
      {
        name: "PinboardShot",
        label: "Local Mac reference flow",
        strength: "Native macOS, instant pinning, every desktop space, opacity, click-through, and Native Retina to 8K output.",
        difference: "Developer ID signing and Apple notarization are trust basics; the real difference is local-first pinning, controlled output, and optional offline watermarking.",
      },
    ],
    comparisonSummary: ["Native Mac", "No account or telemetry", "Screenshots stay local", "Optional offline watermark"],
    privacyEyebrow: "PRIVATE BY DESIGN",
    privacyTitle: "Your screenshots stay\non your Mac.",
    privacyBody: "No account, cloud sync, or telemetry. Captures, annotations, the latest 50 history items, and preferences stay on-device; network access is used only for software updates. Empty or abnormal frames are rejected without replacing your clipboard.",
    privacyPoints: ["Updates-only network access", "No analytics", "Abnormal-frame protection", "Native system frameworks"],
    changelogEyebrow: "CHANGELOG",
    changelogTitle: "Every update,\nclearly documented.",
    changelogBody: "These highlights mirror the GitHub Releases. Open the matching release for complete notes, compatibility details, and installation instructions.",
    changelogLink: "View full release",
    releases: [
      {
        version: currentRelease.version,
        date: currentRelease.date,
        ...currentRelease.en,
      },
      {
        version: "0.5.1",
        date: "2026.07.12",
        label: "Previous",
        title: "Offline invisible watermarking and update settings",
        changes: [
          "Added optional invisible watermarking with a random capture ID and checksum information.",
          "Added local-only project, recipient, and custom-text fields for watermark records.",
          "Added watermark detection for common re-encoding, resizing, JPEG compression, and light cropping scenarios.",
          "Added controls for automatic update checks and check frequency.",
        ],
      },
      {
        version: "0.5.0",
        date: "2026.07.12",
        label: "First release",
        title: "Secure updates and a complete annotation workflow",
        changes: [
          "Added mosaic, pen, rectangle, highlight, arrow, and editable text annotations.",
          "Added Simplified Chinese, Traditional Chinese, and English with runtime switching.",
          "Added the capture entrance animation and pinned-image shadow settings.",
          "Added signed Sparkle updates while keeping network access limited to software updates.",
        ],
      },
    ],
    ctaTitle: "Keep what matters in sight.",
    ctaBody: "Lightweight, native, and focused. Download PinboardShot today.",
    footer: "A fully native screenshot and pinboard tool for macOS.",
    copyright: "Local-first by design.",
  },
} as const;

export default function Home() {
  const [language, setLanguage] = useState<Language>("zh");
  const [demoStep, setDemoStep] = useState(0);
  const [demoPaused, setDemoPaused] = useState(false);
  const content = copy[language];

  /** Hydrate the visitor's local language preference after the server-rendered Chinese default. */
  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      const saved = window.localStorage.getItem("pinboardshot-language") as Language | null;
      const detected: Language = navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
      setLanguage(saved === "zh" || saved === "en" ? saved : detected);
    });

    return () => window.cancelAnimationFrame(frame);
  }, []);

  /** Advance the product story unless the visitor is interacting or prefers reduced motion. */
  useEffect(() => {
    if (demoPaused || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const timer = window.setInterval(() => setDemoStep((step) => (step + 1) % 4), 3200);
    return () => window.clearInterval(timer);
  }, [demoPaused]);

  /** Keep explicit language choices stable across return visits. */
  const selectLanguage = (next: Language) => {
    setLanguage(next);
    window.localStorage.setItem("pinboardshot-language", next);
    document.documentElement.lang = next === "zh" ? "zh-CN" : "en";
  };

  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="PinboardShot home">
          <span className="brand-mark" aria-hidden="true"><i /><i /></span>
          <span>PinboardShot</span>
        </a>
        <nav aria-label={language === "zh" ? "主导航" : "Main navigation"}>
          <a href="#features">{content.nav.features}</a>
          <a href="#workflow">{content.nav.workflow}</a>
          <a href="#compare">{content.nav.compare}</a>
          <a href="#privacy">{content.nav.privacy}</a>
          <a href="#changelog">{content.nav.changelog}</a>
        </nav>
        <div className="header-actions">
          <div className="language-switch" aria-label={language === "zh" ? "语言" : "Language"}>
            <button className={language === "zh" ? "active" : ""} onClick={() => selectLanguage("zh")} aria-pressed={language === "zh"}>中文</button>
            <span aria-hidden="true">/</span>
            <button className={language === "en" ? "active" : ""} onClick={() => selectLanguage("en")} aria-pressed={language === "en"}>EN</button>
          </div>
          <a className="icon-link" href={githubUrl} target="_blank" rel="noreferrer" aria-label={content.repo}>
            <GitHubIcon />
          </a>
          <a className="small-download" href={primaryDownloadUrl}>{content.nav.download}</a>
        </div>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow"><span />{content.eyebrow}</p>
          <h1>{content.title.split("\n").map((line) => <span key={line}>{line}</span>)}</h1>
          <p className="intro">{content.intro}</p>
          <div className="hero-actions">
            <a className="button button-primary" href={primaryDownloadUrl}>{content.download}<span aria-hidden="true">↓</span></a>
            <a className="button button-secondary" href="#features">{content.learn}<span aria-hidden="true">↘</span></a>
          </div>
          <p className="requirement">{content.requirement}</p>
        </div>

        <div className="product-stage" aria-label={language === "zh" ? "PinboardShot 截图贴屏效果示意" : "PinboardShot capture and pin preview"}>
          <div className="selection-frame"><span className="corner corner-a" /><span className="corner corner-b" /><span className="selection-label">{content.selection}</span></div>
          <div className="pin-window">
            <div className="window-bar"><span className="traffic"><i /><i /><i /></span><span>{content.pinned}</span></div>
            <div className="window-content">
              <div className="mock-title" />
              <div className="mock-line line-long" />
              <div className="mock-line line-medium" />
              <div className="mock-grid">
                <div className="mock-canvas"><span className="annotation-box" /><span className="annotation-arrow">↗</span></div>
                <div className="quality-card"><strong>8K</strong><span>Native → 8K</span></div>
              </div>
            </div>
          </div>
          <div className="floating-note"><span>⌘</span><strong>{content.toolbar}</strong></div>
          <div className="stage-glow" />
        </div>
      </section>

      <section className="distribution section" aria-labelledby="distribution-title">
        <div className="distribution-copy">
          <p className="eyebrow"><span />{content.distributionEyebrow}</p>
          <h2 id="distribution-title">{content.distributionTitle.split("\n").map((line) => <span key={line}>{line}</span>)}</h2>
          <p>{content.distributionBody}</p>
          <div className="distribution-links">
            <a href={releaseUrl} target="_blank" rel="noreferrer">{content.checksum}</a>
            <a href={releaseUrl} target="_blank" rel="noreferrer">{content.source}</a>
          </div>
        </div>
        <div className="install-card">
          <strong>{content.previewBadge}</strong>
          <ol>{content.distributionSteps.map((step) => <li key={step}>{step}</li>)}</ol>
          <a className="button button-primary" href={primaryDownloadUrl}>{content.download}<span aria-hidden="true">↓</span></a>
        </div>
      </section>

      <section className="features section" id="features">
        <div className="section-heading">
          <div><p className="eyebrow"><span />{content.featuresEyebrow}</p><h2>{content.featuresTitle.split("\n").map((line) => <span key={line}>{line}</span>)}</h2></div>
          <p className="section-index">{content.demoHint}</p>
        </div>
        <div
          className={`capture-showcase demo-step-${demoStep}`}
          onMouseEnter={() => setDemoPaused(true)}
          onMouseLeave={() => setDemoPaused(false)}
          onFocus={() => setDemoPaused(true)}
          onBlur={() => setDemoPaused(false)}
        >
          <div className="demo-step-list" role="tablist" aria-label={language === "zh" ? "产品演示步骤" : "Product demo steps"}>
            {content.workflow.map(([number, title, body], index) => (
              <button
                key={number}
                type="button"
                role="tab"
                aria-selected={demoStep === index}
                className={demoStep === index ? "active" : ""}
                onClick={() => setDemoStep(index)}
              >
                <span className="demo-number">{number}</span>
                <span className="demo-copy"><strong>{title}</strong><small>{body}</small></span>
                <span className="demo-progress" aria-hidden="true"><i /></span>
              </button>
            ))}
          </div>
          <div className="capture-stage" role="img" aria-label={content.workflow[demoStep][2]}>
            <div className="desktop-menu"><span /><span /><span /><i>PinboardShot</i></div>
            <div className="source-panel">
              <div className="source-bar"><i /><i /><i /></div>
              <div className="source-title" />
              <div className="source-line line-a" />
              <div className="source-line line-b" />
              <div className="source-tiles"><i /><i /><i /></div>
            </div>
            <div className="demo-selection">
              <i className="handle h1" /><i className="handle h2" /><i className="handle h3" /><i className="handle h4" />
              <span className="selection-size">684 × 428</span>
              <span className="drawn-rectangle" />
              <span className="drawn-arrow">↗</span>
              <span className="text-note">Pin this</span>
            </div>
            <div className="annotation-toolbar" aria-hidden="true"><span>▦</span><span>✎</span><span>□</span><span>↗</span><span>T</span><span className="tool-color" /></div>
            <div className="demo-pin">
              <div className="pin-top"><i /><i /><i /><span>{content.pinned}</span></div>
              <div className="pin-art"><span /><i /></div>
            </div>
            <div className="demo-quality"><strong>8K</strong><span>Native → 8K</span></div>
            <div className="demo-cursor" aria-hidden="true">↖</div>
            <div className="demo-status" aria-live="polite"><span />{content.pinStatus[demoStep]}</div>
          </div>
        </div>
        <div className="capability-rail">
          {content.features.slice(4).map(([title, body], index) => (
            <article key={title}><span>0{index + 5}</span><h3>{title}</h3><p>{body}</p></article>
          ))}
        </div>
      </section>

      <section className={`workflow section pin-scene-${demoStep}`} id="workflow">
        <div className="workflow-copy">
          <p className="eyebrow light"><span />{content.pinEyebrow}</p>
          <h2>{content.pinTitle.split("\n").map((line) => <span key={line}>{line}</span>)}</h2>
          <p className="workflow-intro">{content.pinBody}</p>
          <div className="pin-stats">{content.pinStats.map(([label, value]) => <span key={label}><small>{label}</small><strong>{value}</strong></span>)}</div>
        </div>
        <div className="pin-playground" role="img" aria-label={language === "zh" ? "多张贴图、透明度和鼠标穿透动态演示" : "Animated demo of multiple pins, opacity, and click-through"}>
          <div className="playground-grid" />
          <div className="floating-pin pin-one"><div className="mini-bar"><i /><i /><i /></div><div className="pin-gradient pin-gradient-a" /></div>
          <div className="floating-pin pin-two"><div className="mini-bar"><i /><i /><i /></div><div className="pin-lines"><span /><span /><span /></div></div>
          <div className="floating-pin pin-three"><div className="mini-bar"><i /><i /><i /></div><div className="pin-gradient pin-gradient-b" /></div>
          <div className="opacity-control"><span>{language === "zh" ? "透明度" : "Opacity"}</span><div><i /></div><strong>64%</strong></div>
          <div className="passthrough-badge"><i>↗</i><span>{language === "zh" ? "鼠标穿透" : "Click-through"}</span><strong>{language === "zh" ? "已开启" : "On"}</strong></div>
          <div className="playground-cursor">↖</div>
        </div>
      </section>

      <section className="comparison section" id="compare" aria-labelledby="comparison-title">
        <div className="comparison-heading">
          <div>
            <p className="eyebrow"><span />{content.comparisonEyebrow}</p>
            <h2 id="comparison-title">{content.comparisonTitle.split("\n").map((line) => <span key={line}>{line}</span>)}</h2>
          </div>
          <p>{content.comparisonBody}</p>
        </div>
        <div className="comparison-grid">
          {content.comparisonCards.map((card, index) => (
            <article className={card.name === "PinboardShot" ? "comparison-card featured" : "comparison-card"} key={card.name}>
              <div className="comparison-card-top">
                <span>0{index + 1}</span>
                <strong>{card.name}</strong>
              </div>
              <h3>{card.label}</h3>
              <p>{card.strength}</p>
              <div className="comparison-difference">
                <small>{language === "zh" ? "PinboardShot 的取舍" : "PinboardShot's choice"}</small>
                <p>{card.difference}</p>
              </div>
            </article>
          ))}
        </div>
        <div className="comparison-summary">
          {content.comparisonSummary.map((item) => <span key={item}>{item}</span>)}
        </div>
      </section>

      <section className="privacy section" id="privacy">
        <div className="privacy-orbit" aria-hidden="true"><i /><i /></div>
        <div className="privacy-copy">
          <p className="privacy-label">{content.privacyEyebrow}</p>
          <h2>{content.privacyTitle.split("\n").map((line) => <span key={line}>{line}</span>)}</h2>
        </div>
        <div className="privacy-detail"><p>{content.privacyBody}</p><ul>{content.privacyPoints.map((point) => <li key={point}><span aria-hidden="true">✓</span>{point}</li>)}</ul></div>
      </section>

      <section className="changelog section" id="changelog" aria-labelledby="changelog-title">
        <div className="changelog-heading">
          <div>
            <p className="eyebrow"><span />{content.changelogEyebrow}</p>
            <h2 id="changelog-title">{content.changelogTitle.split("\n").map((line) => <span key={line}>{line}</span>)}</h2>
          </div>
          <p>{content.changelogBody}</p>
        </div>
        <div className="release-list">
          {content.releases.map((release, index) => (
            <article className="release" key={release.version}>
              <div className="release-meta">
                <span className="release-index">0{index + 1}</span>
                <time dateTime={release.date.replaceAll(".", "-")}>{release.date}</time>
              </div>
              <div className="release-summary">
                <div className="release-title-row">
                  <h3>PinboardShot {release.version}</h3>
                  <span>{release.label}</span>
                </div>
                <p>{release.title}</p>
              </div>
              <ul>{release.changes.map((change) => <li key={change}>{change}</li>)}</ul>
              <a href={`https://github.com/agent-club/PinboardShot/releases/tag/v${release.version}`} target="_blank" rel="noreferrer">
                {content.changelogLink}<span aria-hidden="true">↗</span>
              </a>
            </article>
          ))}
        </div>
      </section>

      <section className="download-section">
        <div><p className="eyebrow"><span />PINBOARDSHOT FOR MAC</p><h2>{content.ctaTitle}</h2><p>{content.ctaBody}</p></div>
        <a className="button button-primary" href={primaryDownloadUrl}>{content.download}<span aria-hidden="true">↓</span></a>
      </section>

      <footer>
        <div className="footer-brand"><span className="brand-mark" aria-hidden="true"><i /><i /></span><div><strong>PinboardShot</strong><p>{content.footer}</p></div></div>
        <div className="footer-meta">
          <a href={githubUrl} target="_blank" rel="noreferrer">{content.repo}</a>
          <span>macOS 14+</span>
          <span>{content.copyright}</span>
        </div>
      </footer>
    </main>
  );
}
