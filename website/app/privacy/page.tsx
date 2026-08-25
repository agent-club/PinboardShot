import type { Metadata } from "next";
import Link from "next/link";
import { OPENGRAPH_IMAGE_PATH, TWITTER_IMAGE_PATH, absoluteUrl } from "../seo";

const title = "Privacy Policy - PinboardShot";
const description =
  "PinboardShot privacy policy covering the macOS app, website, downloads, updates, local screenshot data, and necessary service logs.";
const canonical = absoluteUrl("/privacy");
const socialImage = absoluteUrl(OPENGRAPH_IMAGE_PATH);
const twitterImage = absoluteUrl(TWITTER_IMAGE_PATH);

export const metadata: Metadata = {
  title,
  description,
  alternates: {
    canonical,
  },
  robots: {
    index: true,
    follow: true,
  },
  openGraph: {
    title,
    description,
    url: canonical,
    siteName: "PinboardShot",
    type: "article",
    locale: "en_US",
    alternateLocale: ["zh_CN"],
    images: [{ url: socialImage, width: 1792, height: 1024, alt: "PinboardShot for macOS" }],
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    images: [twitterImage],
  },
};

const lastUpdated = "August 23, 2026";

export default function PrivacyPolicyPage() {
  return (
    <main className="legal-page">
      <header>
        <Link className="legal-back" href="/">Back to PinboardShot</Link>
        <h1>Privacy Policy</h1>
        <p>
          This page explains how PinboardShot handles data in the macOS app,
          on the website, and during software downloads and updates. It is
          written to match the current local-first product design.
        </p>
      </header>

      <section className="legal-section" aria-labelledby="english-policy">
        <h2 id="english-policy">English</h2>
        <div>
          <p><strong>Last updated:</strong> {lastUpdated}</p>

          <h3>1. Who We Are</h3>
          <p>
            PinboardShot is a native macOS screenshot, annotation, and screen
            pinning app maintained by the PinboardShot project. You can contact
            the project through the public GitHub repository:
            {" "}
            <a href="https://github.com/agent-club/PinboardShot" target="_blank" rel="noreferrer">
              github.com/agent-club/PinboardShot
            </a>.
          </p>

          <h3>2. App Data</h3>
          <p>
            The PinboardShot app does not require an account, does not provide
            cloud sync, and does not include analytics or advertising SDKs.
            Screenshots, annotations, pinned images, recent history, optional
            invisible watermark records, shortcuts, and preferences are
            processed locally on your Mac by default.
          </p>
          <p>
            Screenshot history is stored on your device and can be cleared from
            the app. If you choose to copy, save, share, or upload a screenshot
            through another app or service, that action is controlled by you and
            by the destination you choose.
          </p>
          <p>
            If you explicitly configure a remote OCR plugin and use the OCR
            annotation tool, PinboardShot sends only the image region you selected
            to the Base URL you configured. API Keys are stored in macOS Keychain.
            Capture-history indexing and smart redaction continue to run on-device.
          </p>

          <h3>3. Permissions</h3>
          <p>
            macOS may ask for Screen & System Audio Recording permission so the
            app can capture screen content. The permission is used for capture
            features and does not give PinboardShot a reason to upload your
            screenshots.
          </p>

          <h3>4. Network Use</h3>
          <p>
            By default, the app uses network access for software update checks and
            update downloads. Update requests may be served by GitHub Releases,
            Sparkle appcast files, or hosting/CDN infrastructure. These services
            may process necessary technical information such as IP address,
            request time, user agent, download URL, and basic security logs.
          </p>
          <p>
            A user-configured remote OCR service also receives the selected image
            region and the request fields declared by its plugin manifest. That
            service may process the request under its own terms and privacy policy.
            PinboardShot rejects cross-origin redirects before forwarding authentication.
          </p>

          <h3>5. Website Data</h3>
          <p>
            The website uses Google tag for basic visit measurement. We do not
            enable ad personalization. Analytics storage is enabled by default;
            you can turn analytics off from the website privacy choices. The
            site stores your language preference and privacy choice in local
            storage, and uses that choice to update Google consent settings for
            analytics storage. Hosting providers may still keep necessary
            access, security, and delivery logs.
          </p>

          <h3>6. Showcase Images</h3>
          <p>
            Website and product showcase images use owned photos and interface
            mockups created for PinboardShot. They are used to demonstrate the
            product interface mood and feature concepts, not to depict a
            third-party product or unrelated user content.
          </p>

          <h3>7. Third-Party Services</h3>
          <p>
            Downloads, releases, source code hosting, software updates,
            optional user-configured OCR, website visit measurement, notarization,
            and operating system permissions may involve services operated by
            GitHub, Google, Apple, Cloudflare, an OCR provider chosen by the user,
            or other infrastructure providers. Their processing is governed by
            their own terms and privacy policies.
          </p>

          <h3>8. Your Choices</h3>
          <ul>
            <li>You can avoid automatic update checks and download releases manually.</li>
            <li>You can keep on-device OCR selected, remove a remote OCR API Key from Keychain, or remove a plugin manifest.</li>
            <li>You can clear screenshot history and local preferences from the app or from macOS storage locations.</li>
            <li>You can clear website local storage in your browser.</li>
            <li>You can stop using the app and remove it from your Mac at any time.</li>
          </ul>

          <h3>9. Changes</h3>
          <p>
            This policy may be updated when the product, website, download
            infrastructure, or legal requirements change. The date at the top of
            this page shows when the policy was last updated.
          </p>
        </div>
      </section>

      <section className="legal-section" aria-labelledby="chinese-policy">
        <h2 id="chinese-policy">中文</h2>
        <div>
          <p><strong>最后更新：</strong>2026 年 8 月 23 日</p>

          <h3>1. 我们是谁</h3>
          <p>
            PinboardShot 是一个原生 macOS 截图、标注与贴图工具，由 PinboardShot
            项目维护。你可以通过公开 GitHub 仓库联系项目：
            {" "}
            <a href="https://github.com/agent-club/PinboardShot" target="_blank" rel="noreferrer">
              github.com/agent-club/PinboardShot
            </a>。
          </p>

          <h3>2. 应用数据</h3>
          <p>
            PinboardShot 不要求账号，不提供云同步，也不包含分析或广告 SDK。截图、标注、
            贴图、最近历史、可选隐形水印记录、快捷键和偏好设置默认都在你的 Mac 本机处理。
          </p>
          <p>
            截图历史保存在你的设备上，并可在应用内清理。如果你主动通过其他应用或服务复制、
            保存、分享或上传截图，该行为由你以及你选择的目标服务控制。
          </p>
          <p>
            如果你明确配置远程 OCR 插件并使用 OCR 标注工具，PinboardShot 只会把你框选的
            图片区域发送到你配置的 Base URL。API Key 保存在 macOS 钥匙串中；截图历史索引
            和智能脱敏仍在本机执行。
          </p>

          <h3>3. 系统权限</h3>
          <p>
            macOS 可能会请求“屏幕与系统音频录制”权限，用于实现屏幕捕捉功能。该权限并不
            意味着 PinboardShot 会上传你的截图。
          </p>

          <h3>4. 网络使用</h3>
          <p>
            默认情况下，应用使用网络访问进行软件更新检查和更新包下载。更新请求可能由 GitHub Releases、
            Sparkle appcast 文件或托管/CDN 基础设施提供。这些服务可能处理必要技术信息，
            例如 IP 地址、请求时间、用户代理、下载 URL 和基础安全日志。
          </p>
          <p>
            用户配置的远程 OCR 服务还会收到所选图片区域以及插件 manifest 声明的请求字段。
            该服务可能按其自身条款和隐私政策处理请求。PinboardShot 会在转发鉴权信息前拒绝
            跨来源重定向。
          </p>

          <h3>5. 网站数据</h3>
          <p>
            本网站使用 Google tag 进行基础访问衡量，不启用广告个性化。分析存储默认开启；
            你可以在网站隐私选择中关闭分析。网站会使用本地存储记住你的语言偏好和隐私
            选择，并根据该选择更新 Google 的分析存储同意设置。托管服务仍可能保留必要的
            访问、安全和内容分发日志。
          </p>

          <h3>6. 展示图片</h3>
          <p>
            网站与产品展示图片使用自有照片与 PinboardShot 创建的界面示意素材，用于展示
            产品界面氛围和功能概念，不用于描绘第三方产品或无关用户内容。
          </p>

          <h3>7. 第三方服务</h3>
          <p>
            下载、Release、源码托管、软件更新、用户配置的可选 OCR、网站访问衡量、公证和
            操作系统权限可能涉及 GitHub、Google、Apple、Cloudflare、用户选择的 OCR 服务商
            或其他基础设施服务商。相关处理受这些服务商自己的条款和隐私政策约束。
          </p>

          <h3>8. 你的选择</h3>
          <ul>
            <li>你可以关闭自动更新检查，并手动下载 Release。</li>
            <li>你可以继续使用本机 OCR、从钥匙串移除远程 OCR API Key，或删除插件 manifest。</li>
            <li>你可以在应用内或 macOS 存储位置清理截图历史和本地偏好。</li>
            <li>你可以在浏览器中清除网站本地存储。</li>
            <li>你可以随时停止使用并从 Mac 移除应用。</li>
          </ul>

          <h3>9. 变更</h3>
          <p>
            当产品、网站、下载基础设施或法律要求变化时，本政策可能更新。本页面顶部日期表示
            最近更新时间。
          </p>
        </div>
      </section>
    </main>
  );
}
