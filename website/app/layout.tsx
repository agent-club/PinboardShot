import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { OPENGRAPH_IMAGE_PATH, SITE_URL, TWITTER_IMAGE_PATH, absoluteUrl, localeSeo, seoKeywords } from "./seo";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });
const socialImage = absoluteUrl(OPENGRAPH_IMAGE_PATH);
const twitterImage = absoluteUrl(TWITTER_IMAGE_PATH);

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
      <body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body>
    </html>
  );
}
