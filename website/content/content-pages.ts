export type ContentPageSectionName = "features" | "use-cases" | "compare";

export type ContentPageSection = {
  heading: string;
  paragraphs?: readonly string[];
  bullets?: readonly string[];
};

export type ContentPageSource = {
  label: string;
  href: string;
};

export type ContentPageDefinition = {
  section: ContentPageSectionName;
  slug: string;
  path: string;
  categoryLabel: string;
  eyebrow: string;
  title: string;
  metaTitle: string;
  description: string;
  intro: string;
  lastReviewed: string;
  facts: readonly { label: string; value: string }[];
  sections: readonly ContentPageSection[];
  comparison?: {
    otherProduct: string;
    rows: readonly { topic: string; pinboardShot: string; other: string }[];
  };
  cautions: readonly string[];
  sources: readonly ContentPageSource[];
  relatedPaths: readonly string[];
};

const pinboardShotReadme = "https://github.com/agent-club/PinboardShot/blob/main/README.md";
const pinboardShotLicense = "https://github.com/agent-club/PinboardShot/blob/main/LICENSE";
const pinboardShotPrivacy = "https://pinboardshot.agentclub.dev/privacy";
const pinboardShotSecurity = "https://github.com/agent-club/PinboardShot/blob/main/SECURITY.md";

export const CONTENT_PAGES = [
  {
    section: "features",
    slug: "scrolling-screenshot",
    path: "/features/scrolling-screenshot",
    categoryLabel: "功能详解",
    eyebrow: "SCROLLING SCREENSHOT",
    title: "Mac 滚动截图：手动控制、实时预览与本地拼接",
    metaTitle: "Mac 滚动截图：手动滚动、实时预览与本地拼接 | PinboardShot",
    description:
      "PinboardShot 的 Mac 滚动截图工作流：框选滚动区域、手动滚动、实时查看拼接预览，并把长图保存到剪贴板与本地历史。",
    intro:
      "PinboardShot 不替你控制网页或应用滚动。你先框选需要捕捉的区域，再按自己的节奏滚动内容；应用根据相邻画面的重叠区域持续拼接，并在完成前显示实时预览。",
    lastReviewed: "2026-08-30",
    facts: [
      { label: "滚动方式", value: "用户手动滚动，节奏与停止时机可控" },
      { label: "拼接方式", value: "根据相邻画面的重叠内容自动拼接" },
      { label: "完成前检查", value: "右侧实时预览持续显示长图结果" },
      { label: "结果去向", value: "复制到剪贴板，并进入可配置的本地历史" },
    ],
    sections: [
      {
        heading: "一次滚动截图怎样完成",
        paragraphs: [
          "启动滚动截图后，先选择实际会发生滚动的内容区域。开始捕捉后，用触控板、鼠标或键盘手动向上或向下滚动；聊天记录可从底部向上截取。每次移动都保留上一屏的一部分内容，拼接器才能找到稳定重叠。",
          "实时预览用于在结束前发现错位、重复或缺口。若提示无法匹配，可回滚到已拼接内容后继续；此时直接完成会提醒你只保留已拼接部分。确认结果后，长图可直接复制，也会按历史设置保存在本机。",
        ],
      },
      {
        heading: "适合哪些内容",
        bullets: [
          "较长的网页文章、产品说明和在线文档。",
          "聊天记录、代码片段、日志视图和表格型内容。",
          "需要保留上下文、但不适合拆成多张截图的评审材料。",
          "希望在发送前先本地检查、标注或脱敏的长内容。",
        ],
      },
      {
        heading: "提高拼接稳定性的做法",
        paragraphs: [
          "慢一些滚动，并让相邻画面保留明显重叠；尽量关闭视频、动画和持续变化的悬浮元素。内容结构高度重复时，实时预览比一次滚到底更可靠。",
          "滚动截图有 2.5 亿像素的安全上限，约等于 1 GB 未压缩像素数据。达到上限时应分段捕捉，避免让单张图片占用过多内存。",
        ],
      },
      {
        heading: "本地数据边界",
        paragraphs: [
          "画面捕捉、重叠匹配、拼接与历史保存都在 Mac 上完成。滚动截图本身不需要账号或云服务；只有你另行配置远程 OCR 插件并主动框选 OCR 区域时，所选区域才会发送到指定服务。",
        ],
      },
    ],
    cautions: [
      "这是手动滚动工作流，不是自动控制浏览器或第三方 App 的自动滚屏。",
      "视频、动画、粘性导航和持续变化的内容可能造成重复或错位。",
      "不同 App 的渲染方式不同，不能承诺所有界面都能无误拼接。",
    ],
    sources: [
      { label: "PinboardShot README", href: pinboardShotReadme },
      {
        label: "滚动截图控制器源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/ScrollCaptureController.swift",
      },
      {
        label: "滚动截图拼接器源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/ScrollCaptureStitcher.swift",
      },
    ],
    relatedPaths: ["/features/screen-pinning", "/features/local-ocr-history", "/use-cases/design-review"],
  },
  {
    section: "features",
    slug: "screen-pinning",
    path: "/features/screen-pinning",
    categoryLabel: "功能详解",
    eyebrow: "SCREEN PINNING",
    title: "Mac 贴图：把截图、剪贴板和图片留在工作区上方",
    metaTitle: "Mac 贴图与屏幕固定：透明度、穿透和对比工作区 | PinboardShot",
    description:
      "PinboardShot 的 Mac 贴图能力：从截图、剪贴板或文件创建多张浮动参考，支持缩放、透明度、锁定、鼠标穿透、跨桌面空间和成对比较。",
    intro:
      "贴图的目的不是多开一个图片查看器，而是让正在参考的画面始终留在工作现场。PinboardShot 可以从刚完成的截图、剪贴板或本地图片创建浮动贴图，并围绕阅读、临摹、核对和演示提供控制。",
    lastReviewed: "2026-08-30",
    facts: [
      { label: "来源", value: "截图、剪贴板或本地图片文件" },
      { label: "窗口控制", value: "缩放、20–100% 透明度、锁定与阴影" },
      { label: "交互", value: "可开启鼠标穿透，也可一键恢复交互" },
      { label: "组织", value: "备注、标签、工作区与多张贴图批量管理" },
    ],
    sections: [
      {
        heading: "贴住以后还能做什么",
        paragraphs: [
          "每张贴图都可移动、等比缩放、调节透明度和阴影。锁定用于避免误移动；鼠标穿透让点击落到下方 App，适合照着参考继续写代码、排版或画图。菜单栏中的贴图管理可以恢复全部鼠标交互，避免穿透后找不回窗口。",
          "贴图可保持在 macOS 桌面空间和全屏工作流中，也能限制到当前 Space 或当前 App。具体可见性由每张贴图与工作区设置决定。",
        ],
      },
      {
        heading: "从单张参考到成对比较",
        paragraphs: [
          "两张贴图可以组成比较视图，使用左右并排、差异或混合模式观察变化。它适合核对设计稿与实现、改版前后界面、两份图表或不同环境的截图。",
          "比较功能是本地视觉辅助，不是自动化视觉回归系统：应用不会替你给出通过或失败结论，也不会把结果发送到协作平台。",
        ],
      },
      {
        heading: "工作区、备注与导出",
        bullets: [
          "为贴图添加标题、备注和标签，按任务保存为本地工作区。",
          "将工作区导出为图片、PDF 或 Markdown，交付前仍可自行检查。",
          "可选的工作区恢复默认关闭；启用时最长保留 24 小时。",
          "同时管理多张参考，不要求登录或云同步。",
        ],
      },
      {
        heading: "隐私与网络边界",
        paragraphs: [
          "贴图图片、元数据、工作区和导出流程默认都在本机。PinboardShot Mac 应用不包含账号、云同步或遥测；软件更新和用户主动配置的远程 OCR 是另外两条明确的网络路径。",
        ],
      },
    ],
    cautions: [
      "鼠标穿透会让贴图忽略点击，应从菜单栏贴图管理或贴图菜单恢复。",
      "工作区恢复是可选能力，默认关闭且不是长期备份或云同步。",
      "比较模式帮助人眼核对，不提供自动断言、团队评论或第三方项目管理集成。",
    ],
    sources: [
      { label: "PinboardShot README", href: pinboardShotReadme },
      {
        label: "贴图窗口管理源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/PinWindowManager.swift",
      },
      {
        label: "本地工作区源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/PinWorkspaceStore.swift",
      },
    ],
    relatedPaths: ["/use-cases/design-review", "/compare/pinboardshot-vs-snipaste", "/features/local-ocr-history"],
  },
  {
    section: "features",
    slug: "local-ocr-history",
    path: "/features/local-ocr-history",
    categoryLabel: "功能详解",
    eyebrow: "LOCAL OCR & HISTORY",
    title: "本地 OCR 截图历史：可搜索、可配置，也能彻底清理",
    metaTitle: "Mac 本地 OCR 与可搜索截图历史 | PinboardShot",
    description:
      "PinboardShot 在 Mac 本机维护 10–250 条、1–90 天可配置的截图历史，并用本地 OCR 建立搜索索引；远程 OCR 是独立、默认关闭的可选路径。",
    intro:
      "截图历史只有在能找回内容、又能明确控制保留范围时才有价值。PinboardShot 把最近截图和 OCR 索引保存在 Mac 本机，数量与天数都可配置，并把本地识别和远程 OCR 的数据边界分开。",
    lastReviewed: "2026-08-30",
    facts: [
      { label: "历史数量", value: "可配置保留 10–250 条截图" },
      { label: "保留期限", value: "可配置 1–90 天，并支持主动清理" },
      { label: "默认识别", value: "使用 macOS 本机文字识别建立搜索索引" },
      { label: "远程 OCR", value: "默认关闭，仅发送主动框选的区域" },
    ],
    sections: [
      {
        heading: "历史不是固定的“最近 50 条”",
        paragraphs: [
          "PinboardShot 允许把历史上限设为 10 到 250 条，把保留期设为 1 到 90 天。到期或超过数量的项目会按设置清理，也可以在应用中逐项删除或清空。官网、README 与机器可读说明使用同一范围。",
        ],
      },
      {
        heading: "本地 OCR 怎样参与搜索",
        paragraphs: [
          "截图进入历史后，可在本机提取可搜索文字。历史列表会显示识别状态，支持复制识别结果以及在失败时重试；搜索用索引同样保存在本地。",
          "本地 OCR 适合查找界面文案、错误信息、代码或文档片段。识别准确度受图片清晰度、字号、语言和排版影响，搜索结果不应替代对原图的核对。",
        ],
      },
      {
        heading: "本地 OCR 与远程 OCR 是两条路径",
        bullets: [
          "历史索引默认使用设备端识别，不需要账号或 API Key。",
          "远程 OCR 插件默认关闭，需要用户提供 manifest 和服务配置。",
          "只有主动框选并发起远程 OCR 的图片区域会发送到配置的 Base URL。",
          "远程服务的 API Key 存在 macOS 钥匙串；历史索引与智能脱敏仍不上传。",
        ],
      },
      {
        heading: "适合敏感资料的操作习惯",
        paragraphs: [
          "根据资料敏感度缩短保留期，在分享前检查截图历史与导出内容；不需要远程识别时保持远程 OCR 未配置。应用提供本地边界，但用户主动复制、保存或发送到其他 App 后，后续处理由所选目标决定。",
        ],
      },
    ],
    cautions: [
      "本地 OCR 结果可能有误，涉及账号、金额或代码时应回看原图。",
      "历史不是备份系统；清理、系统迁移或磁盘故障都可能使内容不可恢复。",
      "远程 OCR 由用户选择的服务处理，启用前应检查该服务的条款与隐私政策。",
    ],
    sources: [
      { label: "PinboardShot README", href: pinboardShotReadme },
      {
        label: "截图历史源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/HistoryStore.swift",
      },
      {
        label: "本地文字识别源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/TextRecognitionService.swift",
      },
      {
        label: "远程 OCR 插件源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/OCRPluginService.swift",
      },
    ],
    relatedPaths: ["/features/scrolling-screenshot", "/features/screen-pinning", "/compare/pinboardshot-vs-shottr"],
  },
  {
    section: "use-cases",
    slug: "design-review",
    path: "/use-cases/design-review",
    categoryLabel: "使用场景",
    eyebrow: "DESIGN REVIEW",
    title: "用截图、贴图和本地比较完成一次设计评审",
    metaTitle: "Mac 设计评审工作流：截图、标注、贴图与比较 | PinboardShot",
    description:
      "用 PinboardShot 在 Mac 上捕捉实现、标注问题、把设计参考贴在窗口上方，并用并排、差异或混合模式做本地设计评审。",
    intro:
      "设计评审常见的问题不是缺一张截图，而是参考、实现和说明分散在不同窗口。PinboardShot 把捕捉、标注、持续参考、成对比较和导出串成一个本地工作流。",
    lastReviewed: "2026-08-30",
    facts: [
      { label: "捕捉", value: "区域、窗口、屏幕或滚动长图" },
      { label: "说明", value: "马赛克、画笔、形状、箭头、文字与步骤编号" },
      { label: "核对", value: "贴图、透明度、穿透以及成对比较" },
      { label: "交付", value: "工作区可导出为图片、PDF 或 Markdown" },
    ],
    sections: [
      {
        heading: "第一步：捕捉可复核的上下文",
        paragraphs: [
          "选择能说明问题的最小区域；如果问题跨越长页面，再使用滚动截图保留上下文。确认捕捉前先收紧选区，避免把无关窗口、通知或敏感信息带入评审材料。",
        ],
      },
      {
        heading: "第二步：让标注表达具体问题",
        bullets: [
          "用箭头或矩形指出组件，不用大段文字描述位置。",
          "用步骤编号表达交互顺序，用文字补充期望与实际差异。",
          "在分享前用马赛克或本机智能脱敏处理不应出现的信息。",
          "需要继续核对时，可把相关截图保留为贴图或本地工作区；只需交付时再导出平面结果。",
        ],
      },
      {
        heading: "第三步：把参考贴在实现旁边",
        paragraphs: [
          "把设计稿、目标状态或上一版本贴在浏览器、IDE 或模拟器上方。透明度和鼠标穿透可以让参考存在但不挡操作；限制到当前 Space 或 App，可以避免贴图出现在不相关工作区。",
        ],
      },
      {
        heading: "第四步：成对核对并导出结论",
        paragraphs: [
          "将参考与实现组成比较视图，在左右并排、差异和混合模式之间切换。确认问题后，把相关贴图、备注和标签保存在本地工作区，再按需要导出图片、PDF 或 Markdown。",
          "PinboardShot 不代替 Figma 评论、Issue 跟踪或团队审批。它负责生成清楚、可复核的本地视觉材料，后续协作渠道仍由团队选择。",
        ],
      },
    ],
    cautions: [
      "比较模式是人工评审辅助，不会自动判断像素差异是否通过。",
      "当前没有内建 Figma、Jira、Linear 或团队评论集成。",
      "不要把本地工作区当作团队源文件或长期版本管理系统。",
    ],
    sources: [
      { label: "PinboardShot README", href: pinboardShotReadme },
      {
        label: "贴图比较窗口源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/PinComparisonWindow.swift",
      },
      {
        label: "工作区导出源码",
        href: "https://github.com/agent-club/PinboardShot/blob/main/Sources/PinboardShot/PinWorkspaceExporter.swift",
      },
    ],
    relatedPaths: ["/features/screen-pinning", "/features/scrolling-screenshot", "/compare/pinboardshot-vs-cleanshot-x"],
  },
  {
    section: "compare",
    slug: "pinboardshot-vs-shottr",
    path: "/compare/pinboardshot-vs-shottr",
    categoryLabel: "官方资料对比",
    eyebrow: "PINBOARDSHOT VS SHOTTR",
    title: "PinboardShot 与 Shottr：怎样选择 Mac 截图工具",
    metaTitle: "PinboardShot vs Shottr：Mac 截图、OCR、贴图与隐私对比",
    description:
      "基于 PinboardShot 源码与 Shottr 官方页面，对比 Mac 截图、滚动长图、OCR、贴图、历史、云服务、遥测和许可边界。",
    intro:
      "两款工具都覆盖 Mac 截图、标注、滚动长图、OCR 与贴图，但产品边界不同。下面只比较各自官方公开资料能确认的事实；价格、版本和服务条款以产品当前页面为准。",
    lastReviewed: "2026-08-30",
    facts: [
      { label: "共同能力", value: "截图、滚动长图、标注、OCR 与贴图" },
      { label: "PinboardShot 取向", value: "MIT 开源、Mac 本地参考流与可搜索历史" },
      { label: "Shottr 取向", value: "Mac 截图、像素检查与自动/手动滚动截图" },
      { label: "资料口径", value: "PinboardShot 仓库与 Shottr 官方页面" },
    ],
    sections: [
      {
        heading: "先看结论",
        paragraphs: [
          "如果你重视可审阅源码、MIT 许可、无应用账号/云同步/遥测，以及贴图工作区和本地 OCR 历史，PinboardShot 的边界更直接。",
          "如果你更看重 Shottr 的像素与测量能力、最长可达官方所述 400,000 像素的自动或手动滚动截图，以及可选的 Shottr Cloud 或自有 S3 上传，Shottr 更贴近这类需求。",
        ],
      },
      {
        heading: "数据与网络边界",
        paragraphs: [
          "PinboardShot 的 Mac 应用不需要账号，不提供云同步，也不包含遥测；截图、历史索引和智能脱敏默认留在本机。联网路径包括软件更新，以及用户主动配置并框选区域后的远程 OCR。",
          "Shottr 官方称截图默认保存在本机，OCR 在设备端完成；它另有可选 Shottr Cloud 与用户自有 S3 上传。官方隐私说明还列出可关闭的诊断遥测，以及版本、许可、更新和上传所需的网络行为。",
        ],
      },
      {
        heading: "许可与持续使用",
        paragraphs: [
          "PinboardShot 以 MIT 许可开源并免费分发。Shottr 对大多数功能可长期免费使用，但官方会在使用一段时间后提示购买；商业使用要求许可证，具体档位与价格以 Shottr 购买页为准。",
        ],
      },
    ],
    comparison: {
      otherProduct: "Shottr",
      rows: [
        { topic: "平台", pinboardShot: "macOS 14+；Universal", other: "macOS 10.15+；原生 Mac 应用" },
        { topic: "源码与许可", pinboardShot: "公开源码；MIT 许可；免费", other: "未公开源码；个人可长期免费使用多数功能，商业使用需许可证" },
        { topic: "滚动截图", pinboardShot: "手动滚动、实时预览、自动重叠拼接；2.5 亿像素安全上限", other: "自动与手动模式；官方说明最长 400,000 像素" },
        { topic: "OCR", pinboardShot: "默认本地；可选远程插件只发送主动框选区域", other: "官方说明 OCR 在设备端完成" },
        { topic: "贴图与组织", pinboardShot: "多贴图、穿透、工作区、备注/标签与成对比较", other: "支持截图 pin；官方资料未描述同类保存式工作区" },
        { topic: "历史", pinboardShot: "10–250 条、1–90 天；本地 OCR 搜索", other: "官方功能资料未给出与 PinboardShot 相同的可搜索历史口径" },
        { topic: "云与上传", pinboardShot: "无内建云同步或上传中枢", other: "可选 Shottr Cloud，也可配置自有 S3" },
        { topic: "遥测", pinboardShot: "Mac 应用无遥测", other: "官方说明诊断遥测为可选并可关闭；许可/更新等仍会联网" },
      ],
    },
    cautions: [
      "Shottr 的价格、版本和云服务条款可能变化，购买前应打开官方页面复核。",
      "“未在官方资料中找到”不等于某功能一定不存在，只表示本页不据此作强断言。",
      "滚动截图质量取决于具体内容与应用，两款工具都不应被描述为对所有界面绝对兼容。",
    ],
    sources: [
      { label: "PinboardShot README", href: pinboardShotReadme },
      { label: "PinboardShot MIT License", href: pinboardShotLicense },
      { label: "Shottr 官方网站", href: "https://shottr.cc/" },
      { label: "Shottr FAQ", href: "https://shottr.cc/kb/faq" },
      { label: "Shottr 滚动截图说明", href: "https://shottr.cc/kb/scrollingcapture" },
      { label: "Shottr 隐私说明", href: "https://shottr.cc/blog/privacy" },
      { label: "Shottr 购买页", href: "https://shottr.cc/purchase.html" },
    ],
    relatedPaths: ["/compare/pinboardshot-vs-snipaste", "/compare/pinboardshot-vs-cleanshot-x", "/features/local-ocr-history"],
  },
  {
    section: "compare",
    slug: "pinboardshot-vs-snipaste",
    path: "/compare/pinboardshot-vs-snipaste",
    categoryLabel: "官方资料对比",
    eyebrow: "PINBOARDSHOT VS SNIPASTE",
    title: "PinboardShot 与 Snipaste：Mac 贴图和截图工作流对比",
    metaTitle: "PinboardShot vs Snipaste：Mac 截图、贴图、OCR 与许可对比",
    description:
      "基于 PinboardShot 源码和 Snipaste 官方文档，对比 Mac 截图、贴图、鼠标穿透、虚拟桌面、OCR、历史、平台与许可。",
    intro:
      "Snipaste 以跨平台截图与贴图见长，PinboardShot 则聚焦原生 Mac、本地历史和成对比较工作区。两者都能把图片留在屏幕上方，但适用的系统、许可和组织方式不同。",
    lastReviewed: "2026-08-30",
    facts: [
      { label: "共同能力", value: "截图、基础标注、贴图、透明度与鼠标穿透" },
      { label: "PinboardShot 取向", value: "Mac-only、本地历史、工作区与比较" },
      { label: "Snipaste 取向", value: "Windows、macOS、Linux 的截图与贴图" },
      { label: "资料口径", value: "PinboardShot 仓库与 Snipaste 官方文档" },
    ],
    sections: [
      {
        heading: "先看结论",
        paragraphs: [
          "如果你只在 Mac 上工作，想要开源、免费、滚动截图、本地 OCR 搜索历史、贴图工作区和两图比较，PinboardShot 更符合这个窄而完整的链路。",
          "如果你需要 Windows、macOS 与 Linux 之间相近的截图/贴图习惯，或更看重旋转、镜像、分组等贴图操作与跨平台分发，Snipaste 更合适。",
        ],
      },
      {
        heading: "免费、Pro 与商业使用",
        paragraphs: [
          "PinboardShot 以 MIT 许可开源，个人与商业使用都由该许可条款约束。Snipaste 2.x 对个人非商业用途免费，商业或公司使用需要 Pro；Pro 是 Snipaste 2 大版本的永久许可，未来 3.x 不包含在内。",
          "Snipaste 的桌面版与 Microsoft Store 版是两套独立授权。设备数、地区价格和未来升级条件应在购买时以官网为准。",
        ],
      },
      {
        heading: "OCR、历史与网络边界",
        paragraphs: [
          "PinboardShot 使用本地 OCR 建立历史搜索索引，远程 OCR 默认关闭。Snipaste 当前桌面 Pro 提供文字提取/OCR，并新增腾讯与 OCR.space API 支持；官方没有给出完整的 macOS OCR 数据流说明，因此本页不把它写成完全离线或完全在线。",
          "Snipaste 官方将普通截图、历史与配置描述为本地存储；当前 OCR API 的上传内容、默认引擎与保留方式没有完整说明。应用还会因网络图片、更新检查和 Pro 激活等操作联网；公开资料未描述原生云同步。PinboardShot 同样不提供云同步，并进一步明确 Mac 应用无遥测。",
        ],
      },
    ],
    comparison: {
      otherProduct: "Snipaste",
      rows: [
        { topic: "平台", pinboardShot: "macOS 14+；Universal", other: "Windows、macOS Universal、Linux" },
        { topic: "源码与许可", pinboardShot: "公开源码；MIT 许可；免费", other: "未公开源码；2.x 个人非商业免费，商业使用需 Pro" },
        { topic: "截图", pinboardShot: "区域、窗口、屏幕、延时、重复区域与滚动长图", other: "区域/窗口/元素、延时、重复、历史回放等；官网未把滚动长图列为核心能力" },
        { topic: "贴图", pinboardShot: "缩放、透明度、锁定、穿透、Space/App 限制、工作区", other: "缩放、旋转、镜像、透明度、穿透、分组；虚拟桌面能力部分属于 Pro" },
        { topic: "OCR", pinboardShot: "默认本地；可选远程插件边界明确", other: "桌面 Pro 提供 OCR；macOS 的默认引擎与数据流官方未完整说明" },
        { topic: "历史与组织", pinboardShot: "可搜索本地历史、备注/标签、保存式工作区、成对比较", other: "截图历史与图像组；未找到名为 Workspace 的保存式项目资料库" },
        { topic: "账号与同步", pinboardShot: "无账号、无云同步", other: "桌面 Pro 用邮箱与设备激活；未找到官方云同步说明" },
        { topic: "适合", pinboardShot: "Mac 本地参考、设计核对和敏感资料工作流", other: "跨平台截图与贴图、旋转/镜像/分组等贴图操作" },
      ],
    },
    cautions: [
      "Snipaste 没有逐项发布三平台完整功能矩阵，桌面通用说明不能等同于每个平台行为完全一致。",
      "Snipaste OCR 的默认服务、是否完全本地和数据保留方式在现有官方资料中不明确。",
      "本页没有把 Snipaste 的图像组、白板或历史改称为保存式 Workspace。",
    ],
    sources: [
      { label: "PinboardShot README", href: pinboardShotReadme },
      { label: "PinboardShot MIT License", href: pinboardShotLicense },
      { label: "Snipaste 官方网站", href: "https://www.snipaste.com/" },
      { label: "Snipaste 下载与更新日志", href: "https://www.snipaste.com/download.html" },
      { label: "Snipaste Pro 功能对比", href: "https://docs.snipaste.com/zh-cn/pro" },
      { label: "Snipaste 隐私政策", href: "https://www.snipaste.com/privacy_policy.html" },
      { label: "Snipaste 激活说明", href: "https://docs.snipaste.com/activation-guide-desktop" },
    ],
    relatedPaths: ["/compare/pinboardshot-vs-shottr", "/compare/pinboardshot-vs-cleanshot-x", "/features/screen-pinning"],
  },
  {
    section: "compare",
    slug: "pinboardshot-vs-cleanshot-x",
    path: "/compare/pinboardshot-vs-cleanshot-x",
    categoryLabel: "官方资料对比",
    eyebrow: "PINBOARDSHOT VS CLEANSHOT X",
    title: "PinboardShot 与 CleanShot X：本地截图工具还是完整内容套件",
    metaTitle: "PinboardShot vs CleanShot X：截图、录屏、Cloud 与贴图对比",
    description:
      "基于 PinboardShot 源码与 CleanShot 官方页面，对比 Mac 截图、滚动长图、录屏、OCR、浮动截图、历史、Cloud、价格与安全边界。",
    intro:
      "CleanShot X 是覆盖截图、完整录屏与可选 Cloud 分享的商业套件；PinboardShot 则以开源、本地优先的截图、标注和贴图为主，并提供最长 60 秒的无声区域短录屏。选择取决于你需要的录屏范围和分享方式。",
    lastReviewed: "2026-08-30",
    facts: [
      { label: "共同能力", value: "Mac 截图、滚动长图、标注、OCR 与浮动参考" },
      { label: "PinboardShot 取向", value: "开源免费、无应用账号或 Cloud、专注本地参考流" },
      { label: "CleanShot X 取向", value: "截图、录屏、Quick Access 与可选 Cloud 套件" },
      { label: "资料口径", value: "PinboardShot 仓库与 CleanShot 官方页面" },
    ],
    sections: [
      {
        heading: "先看结论",
        paragraphs: [
          "如果你需要长时间录屏、GIF、摄像头/系统音频、Quick Access，以及可选的托管分享、品牌和团队能力，CleanShot X 的覆盖范围明显更大。",
          "如果你只需要截图、标注、滚动长图、贴图、可搜索本地历史和比较工作区，并希望使用 MIT 开源、免费且不含账号/云同步/遥测的 Mac 应用，PinboardShot 的边界更简单。",
        ],
      },
      {
        heading: "Cloud 不是 CleanShot X 本地功能的硬前提",
        paragraphs: [
          "CleanShot 官方 FAQ 说明，一次性许可证路径不需要 Cloud 才能使用桌面 App 功能；Cloud 用于上传与分享。Cloud Pro 则依赖 Cloud 账号激活，并提供团队、安全和品牌能力。",
          "普通分享链接不应被描述为等同私密存储；CleanShot 官方条款提醒链接可能被第三方猜中，Pro 的密码、过期与自毁控制需要另行启用。",
        ],
      },
      {
        heading: "本地处理与公开资料边界",
        paragraphs: [
          "CleanShot 官方明确 OCR 在设备端处理，并公开 Developer ID、Apple 公证、Hardened Runtime 与更新签名等安全信息。它的桌面使用遥测和崩溃报告数据流在现有公开页中没有完整说明，因此本页保持未知，不据此断言有或没有。",
          "PinboardShot 的源码、隐私政策和安全策略公开可查，Mac 应用明确无遥测；它提供无声区域短录屏，但没有内建 Cloud 分享或团队能力。",
        ],
      },
    ],
    comparison: {
      otherProduct: "CleanShot X",
      rows: [
        { topic: "平台", pinboardShot: "macOS 14+；Universal", other: "macOS 10.15+；无 Windows 版" },
        { topic: "源码与价格", pinboardShot: "公开源码；MIT 许可；免费", other: "未公开源码；一次性 App 许可与 Cloud Pro 订阅，价格以官网为准" },
        { topic: "截图与滚动", pinboardShot: "区域、窗口、屏幕、延时、重复区域、手动滚动拼接", other: "区域、窗口、全屏、定时与滚动截图，官方称几乎适用于每个 App" },
        { topic: "录屏", pinboardShot: "最长 60 秒的无声区域 MP4，可预览并裁剪首尾；不支持 GIF 或音频", other: "MP4/GIF、麦克风、系统音频、摄像头、按键与视频编辑" },
        { topic: "OCR", pinboardShot: "默认设备端；可选远程插件", other: "官方明确在设备端处理" },
        { topic: "浮动参考", pinboardShot: "多贴图、穿透、工作区、备注/标签与成对比较", other: "Floating Screenshots、透明度、定位与 Lock Mode" },
        { topic: "历史", pinboardShot: "10–250 条、1–90 天；本地 OCR 搜索", other: "Capture History 最多一个月；公开页未完整说明存储与同步边界" },
        { topic: "账号与 Cloud", pinboardShot: "无账号、无云同步或托管分享", other: "一次性许可可不用 Cloud；Cloud Pro 使用账号并提供托管与团队能力" },
      ],
    },
    cautions: [
      "CleanShot X 的价格和 Cloud 方案会变化，页面只描述核对时的产品结构，不固化报价。",
      "CleanShot 官方称滚动截图“几乎适用于每个 App”，这不是对所有应用绝对兼容的承诺。",
      "CleanShot 桌面遥测与崩溃报告的完整数据流在公开资料中不明确，本页不作推断。",
    ],
    sources: [
      { label: "PinboardShot README", href: pinboardShotReadme },
      { label: "PinboardShot MIT License", href: pinboardShotLicense },
      { label: "PinboardShot 隐私政策", href: pinboardShotPrivacy },
      { label: "PinboardShot 安全策略", href: pinboardShotSecurity },
      { label: "CleanShot 官方网站", href: "https://cleanshot.com/" },
      { label: "CleanShot 功能页", href: "https://cleanshot.com/features" },
      { label: "CleanShot 定价页", href: "https://cleanshot.com/pricing" },
      { label: "CleanShot FAQ", href: "https://cleanshot.com/faq" },
      { label: "CleanShot Security", href: "https://cleanshot.com/security" },
      { label: "CleanShot Cloud 条款", href: "https://cleanshot.com/legal/cloud/terms" },
    ],
    relatedPaths: ["/compare/pinboardshot-vs-shottr", "/compare/pinboardshot-vs-snipaste", "/use-cases/design-review"],
  },
] as const satisfies readonly ContentPageDefinition[];

export const CONTENT_PAGE_PATHS = CONTENT_PAGES.map((page) => page.path);

export function getContentPage(section: ContentPageSectionName, slug: string) {
  return CONTENT_PAGES.find((page) => page.section === section && page.slug === slug);
}

export function getContentPageByPath(path: string) {
  return CONTENT_PAGES.find((page) => page.path === path);
}

export function contentPageParams(section: ContentPageSectionName) {
  return CONTENT_PAGES.filter((page) => page.section === section).map((page) => ({ slug: page.slug }));
}
