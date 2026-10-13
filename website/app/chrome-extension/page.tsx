import type { Metadata } from "next";
import Link from "next/link";
import { OPENGRAPH_IMAGE_PATH, TWITTER_IMAGE_PATH, absoluteUrl } from "../seo";

const title = "PinboardShot Browser Capture — Chrome Extension for Long Web Pages";
const description =
  "Capture a long Chrome web page and open it in the PinboardShot app on your Mac. Learn how to install and use the extension, its limits, and how it handles page data.";
const canonical = absoluteUrl("/chrome-extension");
const storeUrl = "https://chromewebstore.google.com/detail/pinboardshot-browser-capt/kjpleeeibdicdoljjhoahhnkggncglac";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical },
  robots: { index: true, follow: true },
  openGraph: {
    title,
    description,
    url: canonical,
    siteName: "PinboardShot",
    type: "article",
    locale: "en_US",
    alternateLocale: ["zh_CN"],
    images: [{ url: absoluteUrl(OPENGRAPH_IMAGE_PATH), width: 1920, height: 990, alt: "PinboardShot for macOS" }],
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    images: [absoluteUrl(TWITTER_IMAGE_PATH)],
  },
};

export default function ChromeExtensionPage() {
  return (
    <main className="legal-page">
      <header>
        <Link className="legal-back" href="/">Back to PinboardShot / 返回首页</Link>
        <h1>PinboardShot Browser Capture</h1>
        <p>
          A Chrome extension for capturing long web pages into the PinboardShot Mac app.
          Chrome 网页长截图扩展：在浏览器中采集，再交给 Mac 上的 PinboardShot 合成与编辑。
        </p>
      </header>

      <section className="legal-section" lang="en" aria-labelledby="extension-english">
        <h2 id="extension-english">English</h2>
        <div>
          <h3>What it does</h3>
          <p>
            Start a capture from the extension toolbar, its side panel, or the ⌘⇧Y shortcut.
            The extension captures the active page in image sections, sends them to the locally
            installed PinboardShot app through Chrome Native Messaging, and restores the page&apos;s
            scroll position when it finishes. The app joins the sections and opens the image for editing.
            You can pause, resume, stop and save a partial capture, or cancel.
          </p>

          <h3>Choose an installation method</h3>
          <ol>
            <li><Link href="/download">Install and open PinboardShot on your Mac</Link>.</li>
            <li>In the app, open Settings → Preferences and choose <strong>Download locally</strong> or <a href={storeUrl}>Install from the Chrome Web Store</a>.</li>
            <li>For the local copy, open <code>chrome://extensions</code>, turn on Developer mode, choose Load unpacked, and select the exported folder in Downloads. Keep that folder in place.</li>
            <li>In PinboardShot, open Settings → Preferences → Chrome Web Capture and choose Connect local app.</li>
            <li>Open an ordinary web page and start a capture from the extension button or ⌘⇧Y. Keep that tab active until the capture finishes.</li>
          </ol>
          <p>
            When PinboardShot starts, it registers the fixed IDs for both the bundled local extension and the Chrome Web Store extension with Chrome Native Messaging. The bundled local extension version 0.2.2 is available now. Its matching Chrome Web Store update is awaiting review and is not available from the store until approval. Chrome manages store extension updates separately from Mac app updates.
          </p>
          <p>
            After updating PinboardShot, download the local extension again and load the newly exported folder in Chrome. Keep Chrome 116 or later and macOS 14 or later.
          </p>

          <h3>Supported pages and limits</h3>
          <p>
            The extension works on ordinary HTTP and HTTPS pages whose main document scrolls.
            Chrome internal pages, protected pages, and independently scrolling regions are not
            supported. Very long, changing, or continuously loading pages may reach capture limits
            or fail. The extension does not claim a partial image is a complete page.
          </p>

          <h3>Page data and privacy</h3>
          <p>
            The extension periodically sends a Native Messaging hello to check protocol capabilities: its background checks every minute and its open side panel retries every five seconds. This exchange does not read web pages or take screenshots. PinboardShot updates the connection status from a local receipt. Only after you start a capture does the extension check the active tab URL, read the selected
            page&apos;s content and scroll geometry, and capture visible image sections. It transfers
            those sections to the app on the same Mac through Native Messaging. The app temporarily
            stores and assembles them locally and cleans up incomplete sessions. The extension does
            not send page URLs, titles, or screenshots to a PinboardShot server. A capture can still
            contain personal information visible on the page, so review the result before sharing it.
          </p>
          <p>
            The extension uses this data only for the capture and controls you request. It does not
            sell the data or use it for advertising. See the <Link href="/privacy">privacy policy</Link>
            {" "}for the full data handling description. The website itself has separate visit
            measurement and privacy choices described there.
          </p>
        </div>
      </section>

      <section className="legal-section" lang="zh-CN" aria-labelledby="extension-chinese">
        <h2 id="extension-chinese">中文</h2>
        <div>
          <h3>扩展能做什么</h3>
          <p>
            你可以从扩展按钮、侧栏或 ⌘⇧Y 快捷键发起截图。扩展按分段截取当前网页，
            通过 Chrome Native Messaging 交给同一台 Mac 上的 PinboardShot 合成，
            完成后恢复网页原来的滚动位置，并在应用中打开图片供编辑。采集过程中可以暂停、
            继续、停止并保存已截取部分，或取消。
          </p>

          <h3>选择安装方式</h3>
          <ol>
            <li><Link href="/download">安装并打开 Mac 版 PinboardShot</Link>。</li>
            <li>在应用“设置 → 偏好”中选择“下载到本地”或<a href={storeUrl}>“从商店安装”</a>。</li>
            <li>本地版本下载后，打开 <code>chrome://extensions</code>，开启“开发者模式”，选择“加载已解压的扩展程序”，并选取下载目录中的导出文件夹。请保留这个文件夹。</li>
            <li>在 PinboardShot“设置 → 偏好 → Chrome 网页长截图”中点击“连接本机应用”。</li>
            <li>打开普通网页，点击扩展按钮或按 ⌘⇧Y 开始采集；完成前不要切换该标签页。</li>
          </ol>
          <p>
            PinboardShot 启动时会为内置本地插件和 Chrome 应用商店插件这两个固定 ID 自动注册 Native Messaging。本地内置的 0.2.2 版本现在即可使用；对应的 Chrome 应用商店更新仍在等待审核，通过后才会在商店提供。Chrome 会独立管理商店插件更新。
          </p>
          <p>
            PinboardShot 更新后，请重新下载本地插件，并在 Chrome 中加载新导出的文件夹。需要 Chrome 116 或更新版本，以及 macOS 14 或更新版本。
          </p>

          <h3>支持范围与限制</h3>
          <p>
            扩展支持以主文档滚动的普通 HTTP、HTTPS 网页，不支持 Chrome 内部页、受保护页面
            或独立滚动区域。特别长、持续变化或不断加载的页面可能达到采集上限或采集失败；
            扩展不会把不完整的结果标为整页截图。
          </p>

          <h3>网页数据与隐私</h3>
          <p>
            扩展会定期通过 Native Messaging 发送 hello 以检查协议能力：后台每分钟检查一次，
            打开的侧栏每五秒重试一次。这个过程不会读取网页或截图；PinboardShot 根据本机收据更新连接状态。
            只有你开始截图后，扩展才会检查当前标签页 URL、读取所选网页内容和滚动尺寸，
            截取可见画面分段，再通过 Native Messaging 发送到同一台 Mac 上的应用。
            应用在本机临时存储、合成分段并清理未完成的会话。扩展不会把网页 URL、标题
            或截图发送到 PinboardShot 服务器。截图仍可能包含页面上的个人信息，分享前请检查内容。
          </p>
          <p>
            扩展仅为你请求的截图及相关控制使用这些数据，不出售数据，也不用于广告。
            完整的数据处理说明见<Link href="/privacy">隐私政策</Link>；网站本身的访问衡量
            与隐私选择也在该页另行说明。
          </p>
        </div>
      </section>
    </main>
  );
}
