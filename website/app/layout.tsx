import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import {
  GOOGLE_TAG_ID,
  OPENGRAPH_IMAGE_PATH,
  SITE_URL,
  TWITTER_IMAGE_PATH,
  absoluteUrl,
  localeSeo,
  seoKeywords,
} from "./seo";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });
const socialImage = absoluteUrl(OPENGRAPH_IMAGE_PATH);
const twitterImage = absoluteUrl(TWITTER_IMAGE_PATH);
const googleSiteVerification = process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION?.trim();

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "PinboardShot - Mac 截图、标注与贴图工具",
  description: localeSeo.zh.description,
  applicationName: "PinboardShot",
  authors: [{ name: "PinboardShot" }],
  creator: "PinboardShot",
  publisher: "PinboardShot",
  keywords: seoKeywords,
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/icon.png", type: "image/png" },
    ],
    apple: [
      { url: "/apple-icon.png", type: "image/png" },
      { url: "/apple-touch-icon.png", type: "image/png" },
    ],
  },
  alternates: {
    canonical: SITE_URL,
    languages: {
      "zh-CN": absoluteUrl(localeSeo.zh.path),
      en: absoluteUrl(localeSeo.en.path),
      "x-default": SITE_URL,
    },
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  ...(googleSiteVerification
    ? {
        verification: {
          google: googleSiteVerification,
        },
      }
    : {}),
  openGraph: {
    title: "PinboardShot - Mac 截图、标注与贴图工具",
    description: localeSeo.zh.description,
    url: SITE_URL,
    siteName: "PinboardShot",
    type: "website",
    locale: "zh_CN",
    alternateLocale: ["en_US"],
    images: [{ url: socialImage, width: 1792, height: 1024, alt: "PinboardShot for macOS" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "PinboardShot - Mac 截图、标注与贴图工具",
    description: localeSeo.zh.description,
    images: [twitterImage],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <head>
        <script async src={`https://www.googletagmanager.com/gtag/js?id=${GOOGLE_TAG_ID}`} />
        <script
          dangerouslySetInnerHTML={{
            __html: `
window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
var pinboardshotAnalyticsConsent = "granted";
try {
  pinboardshotAnalyticsConsent = localStorage.getItem("pinboardshot-privacy-consent-v1") === "essential" ? "denied" : "granted";
} catch (_) {}
gtag("consent", "default", {
  ad_storage: "denied",
  ad_user_data: "denied",
  ad_personalization: "denied",
  analytics_storage: pinboardshotAnalyticsConsent
});
gtag("js", new Date());
gtag("config", "${GOOGLE_TAG_ID}");
`.trim(),
          }}
        />
      </head>
      <body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body>
    </html>
  );
}
